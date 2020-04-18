from pprint import pprint
import pexpect
import click
import yaml
import json
import re
import os
import logzero
import logging
import pathlib
from pathlib import Path
import textwrap
from log import log, setup_logger
from input import hidden_multi_input
import xml.etree.ElementTree as ET
import xml
from io import StringIO
from os import path
import threading
import signal
import sys
import time
from pexpect import pxssh
from cloudlab import Cloudlab, UnknownStateError, OperationFailed
import getpass
import traceback


HOST_CONFIG_REGEX = re.compile(r'(?m)^((?:readonly )?[A-Z_]+_HOSTS?)="?.*"?$')
thread_queue = []
term_cond = threading.Condition()
stopping = False
PROMPT = "$"
cloudlab = None
cloudlab_lock = threading.Lock()


class Test:
    def __init__(self, id, options, experiment):
        self._id = id
        self._options = options
        self._experiment = experiment

    def id(self):
        return self._id

    def options(self):
        return self._options

    def experiment(self):
        return self._experiment

    def __repr__(self):
        return f"[{self._id}] - {self._experiment}:\n{json.dumps(self._options)}"


def wait(delay):
    term_cond.acquire()
    term_cond.wait(timeout=delay)
    term_cond.release()
    return stopping


class TestFailed(Exception):
    pass


class ExitEarly(Exception):
    pass


class ExecutionLogWrapper(object):
    def __init__(self, outer, **args):
        self._outer = outer
        self._args = args

    def __enter__(self):
        logger = setup_logger(**self._args)
        self._original = self._outer._logger
        self._outer._logger = logger

    def __exit__(self, ex_type, ex_value, traceback):
        self._outer._logger = self._original


class TestExecutionThread(threading.Thread):
    def __init__(self, test, hostname, config_path, log_path, results_path, config, experiment):
        threading.Thread.__init__(self)
        self._test = test
        self._hostname = hostname
        self._config_path = config_path
        self._log_path = log_path
        self._results_path = results_path
        self._config = config
        self._logger = log
        self._experiment = experiment

    def log_msg(self, msg):
        return f"[{self._test.id()}] {msg}"

    def log(self, level, message, external=False, internal=False):
        logger = None
        if internal:
            if self._logger != log:
                logger = self._logger
        elif external:
            logger = log
        else:
            logger = self._logger

        if logger is not None:
            method = getattr(logger, level)
            if method is not None:
                method(self.log_msg(message))

    def info(self, message, external=False, internal=False):
        self.log("info", message, external=external, internal=internal)

    def error(self, message, external=False, internal=False):
        self.log("error", message, external=external, internal=internal)

    def debug(self, message, external=False, internal=False):
        self.log("debug", message, external=external, internal=internal)

    def warning(self, message, external=False, internal=False):
        self.log("warning", message, external=external, internal=internal)

    def fatal(self, message, external=False, internal=False):
        self.log("fatal", message, external=external, internal=internal)

    def custom_logger(self, **kwargs):
        return ExecutionLogWrapper(self, logfile=self._log_path, name=self._test.id(),
                                   disableStderrLogger=True, colors=False, indent=False,
                                   **kwargs)

    def transfer(self, local_src=None, local_dest=None, remote_path=None, retry_count=1):
        cert_path = self._config.get("ssh_cert", "id_rsa")
        username = self._config.get("username", "root")
        retry_delay = self._config.get("retry_delay", 120)

        prelude = ['-o', 'UserKnownHostsFile=/dev/null',
                   '-o', 'StrictHostKeyChecking=no',
                   '-i', cert_path]
        hoststring = f"{username}@{self._hostname}:{remote_path}"

        to_remote = False
        if local_src is None:
            # Transfer from remote
            args = [*prelude, hoststring, local_dest]
        else:
            # Transfer to remote
            to_remote = True
            args = [*prelude, local_src, hoststring]

        self.debug(
            f"Transferring file '{local_src if to_remote else local_dest}' {'to' if to_remote else 'from'} {hoststring} with options {json.dumps(prelude)}; -i {cert_path}; retry_delay={retry_delay}, retry_count={retry_count}")

        for i in range(retry_count):
            child = pexpect.spawn(command="scp", args=args)
            child.expect(pexpect.EOF)
            child.close()

            if child.exitstatus is not None and child.exitstatus == 0:
                # Successful
                return True
            else:
                if i < retry_count - 1:
                    # Retry sending
                    if to_remote:
                        self.warning(
                            f"Failed to transfer {local_src} to host {self._hostname}; retrying in {retry_delay}s", external=True)
                        self.warning(
                            f"Failed to transfer {local_src} to remote; retrying in {retry_delay}s", internal=True)
                    else:
                        self.warning(
                            f"Failed to transfer {remote_path} from host {self._hostname}; retrying in {retry_delay}s", external=True)
                        self.warning(
                            f"Failed to transfer {remote_path} from remote; retrying in {retry_delay}s", internal=True)
                    if wait(retry_delay):
                        raise ExitEarly()
                else:
                    if to_remote:
                        self.error(
                            f"Failed to transfer {local_src} to host {self._hostname} after {retry_count} retries", external=True)
                        self.error(
                            f"Failed to transfer {local_src} to remote after {retry_count} retries", internal=True)
                    else:
                        self.error(
                            f"Failed to transfer {remote_path} from host {self._hostname} after {retry_count} retries", external=True)
                        self.error(
                            f"Failed to transfer {remote_path} from remote after {retry_count} retries", internal=True)
                    raise TestFailed()

    def terminal(self, retry_count=1):
        retry_delay = self._config.get("retry_delay", 120)
        cert_path = self._config.get("ssh_cert", "id_rsa")
        username = self._config.get("username", "root")
        server = self._hostname
        options = dict(StrictHostKeyChecking="no",
                       UserKnownHostsFile="/dev/null")
        ssh = pxssh.pxssh(options=options)
        self.debug(
            f"SSHing into {username}@{server} with options {json.dumps(options)}; -i {cert_path}; retry_delay={retry_delay}, retry_count={retry_count}")

        for i in range(retry_count):
            try:
                ssh.login(server, username=username, ssh_key=cert_path)
            except pxssh.ExceptionPxssh:
                # Retry connecting
                if i < retry_count - 1:
                    self.warning(
                        f"Failed to attach ssh terminal to host {self._hostname}; retrying in {retry_delay}s", external=True)
                    self.warning(
                        f"Failed to attach ssh terminal to remote; retrying in {retry_delay}s", internal=True)
                    if wait(retry_delay):
                        raise ExitEarly()
                else:
                    self.error(
                        f"Failed to attach ssh terminal to host {self._hostname} after {retry_count} retries", external=True)
                    self.error(
                        f"Failed to attach ssh terminal to remote after {retry_count} retries", internal=True)
                    raise TestFailed()
            else:
                return ssh

    def run_sequence(self, ssh, sequence=[], retry_count=1, timeout=30):
        retry_delay = self._config.get("retry_delay", 120)
        self.debug(
            f"Executing sequence {sequence} with options retry_delay={retry_delay}, retry_count={retry_count}")

        for i in range(retry_count):
            for command in sequence:
                ssh.sendline(command)
                output = ""
                while not ssh.prompt(timeout=timeout):
                    output += ssh.before.decode()
                    ssh.sendcontrol('c')
                output += ssh.before.decode()

                ssh.sendline("echo $?")
                ssh.prompt(timeout=10)

                result = ssh.before.decode().strip().splitlines()
                if len(result) > 0:
                    try:
                        exitcode = int(result[-1])
                    except TypeError:
                        self.warning(
                            f"Couldn't decode exit code from command {command}: {result}")
                        exitcode = 1

                self.debug(f"[{exitcode}] {output}")

                if exitcode != 0:
                    # Assume failed, flag for retry
                    if i < retry_count - 1:
                        self.warning(
                            f"Failed to execute command {command} in sequence to host {self._hostname}; retrying in {retry_delay}s", external=True)
                        self.warning(
                            f"Failed to execute command {command} in sequence to remote; retrying in {retry_delay}s", internal=True)
                        if wait(retry_delay):
                            ssh.close()
                            raise ExitEarly()
                        else:
                            break
                    else:
                        self.error(
                            f"Failed to execute command {command} in sequence to host {self._hostname} after {retry_count} retries", external=True)
                        self.error(
                            f"Failed to execute command {command} in sequence to remote after {retry_count} retries", internal=True)
                        ssh.close()
                        raise TestFailed()
            return

    def run(self):
        try:
            # Create a silent logger that only writes to files
            with self.custom_logger():
                self.info(
                    f"Starting execution thread ({self._hostname})", external=True)
                self.info("Beginning setup")
                self.setup()
                self.info("Finishing setup")
                self.info("Beginning execute")
                self.execute()
                self.info("Finishing execute")
                self.info("Beginning teardown")
                self.teardown()
                self.info("Finishing teardown")
        except ExitEarly:
            self.warning("Exiting test early")
        except TestFailed:
            self.error("Failed test; exiting")
        else:
            self.info(
                f"Exiting execution thread ({self._hostname})", external=True)

    def setup(self):
        # Transfer SSH certificate
        cert_path = self._config.get("ssh_cert", "id_rsa")
        self.info(
            f"Transfering the SSH certificate from {cert_path} to remote:.ssh/id_rsa")
        self.transfer(local_src=cert_path,
                      remote_path=".ssh/id_rsa", retry_count=10)

        # Transfer rendered config file
        remote_config = self._config.get("remote_config", "config.sh")
        self.info(
            f"Transfering rendered config file from {self._config_path} to remote:{remote_config}")
        self.transfer(local_src=self._config_path,
                      remote_path=remote_config, retry_count=10)

    def execute(self):
        # Attach a remote terminal to the executor host
        self.info(f"Attaching a remote terminal to the executor host")
        ssh = self.terminal(retry_count=10)

        # Clone the repo
        repo = self._config.get("repo")
        remote_folder = "repo"
        self.info(f"Cloning the repo {repo} into remote:{remote_folder}")
        clone_sequence = [f'sudo rm -rf {remote_folder}',
                          f'git clone "{repo}" {remote_folder}']
        self.run_sequence(ssh, sequence=clone_sequence, retry_count=10)

        # Copy the config file into place
        experiments_path = self._config.get(
            "experiments_path", "experiments")
        self._remote_experiment_path = path.join(
            remote_folder,
            experiments_path,
            self._test.experiment())
        remote_config = self._config.get("remote_config", "config.sh")
        dest_config_path = path.join(
            self._remote_experiment_path,
            "conf",
            remote_config)
        self.debug(
            f"Copy the config file from remote:{remote_config} into place at remote:{dest_config_path}")
        self.run_sequence(
            ssh, sequence=[f'mv {remote_config} {dest_config_path}'], retry_count=10)

        # Change the working directory to the experiment root (eventual destination of results)
        self.debug(
            f"Change the working directory to remote:{self._remote_experiment_path}")
        self.run_sequence(
            ssh, sequence=[f'cd {self._remote_experiment_path}'], retry_count=1)

        # Run the primary script
        script_path = './scripts/run.sh'
        self.info(f"Running primary script at remote:{script_path}")
        ssh.sendline(script_path)
        while not ssh.prompt(timeout=120):
            self.debug(f"\n{ssh.before.decode().strip()}")
            if ssh.before:
                ssh.expect(r'.+')
        self.debug(f"\n{ssh.before.decode().strip()}")
        self.info("Finished primary script")
        ssh.logout()

    def teardown(self):
        # Move the results tar to /results/{id}.tar.gz
        results_path = path.join(
            self._remote_experiment_path, "results.tar.gz")
        self.debug(
            f"Moving the results tar from remote:{results_path} to {self._results_path}")
        self.transfer(remote_path=results_path,
                      local_dest=self._results_path, retry_count=5)

        # Terminate the experiment on cloudlab
        try:
            cloudlab_lock.acquire()
            cloudlab.terminate(self._experiment)
        except OperationFailed as ex:
            log.error("Could not terminate experiment on cloudlab:")
            log.error(ex)
        except UnknownStateError as ex:
            log.error(
                "Unknown state reached while terminating experiment on cloudlab driver:")
            log.error(ex)
        except Exception as ex:
            log.error(
                "Encountered error while terminating experiment on cloudlab driver:")
            log.error(ex)
        finally:
            cloudlab_lock.release()


@click.command()
@click.option("--config", "-c", prompt="Automation config YAML file")
@click.option("--repo_path", "-r", prompt="Path to locally cloned repo")
@click.option("--cert", "-C", prompt="Path to private SSL certificate", default="~/.ssh/id_rsa", required=False)
@click.option("--threads", "-t", prompt="Maximum concurrency for running experiments", default=1, required=False)
@click.option("--password", "-p", prompt="Path to file containing password", default=None, required=False)
@click.option("--headless/--no-headless", prompt="Run chrome driver in headless mode", default=False)
def main(config=None, repo_path=None, cert=None, threads=None, password=None, headless=False):
    if config is None:
        return

    config_dict = load_config(config)
    if config_dict is None:
        return

    if "ssh_cert" not in config_dict:
        config_dict["ssh_cert"] = cert

    if "max_concurrency" not in config_dict:
        config_dict["max_concurrency"] = threads

    if "password_path" not in config_dict:
        config_dict["password_path"] = password

    if "headless" not in config_dict:
        config_dict["headless"] = headless

    run(config_dict, repo_path)


def run(config, repo_path):
    log.info("Starting automated experiment execution")
    if "tests" not in config or len(config["tests"]) == 0:
        log.error("No tests found. Exiting")
        return

    if "repo" not in config:
        log.error("No repo found. Exiting")
        return

    # Make local directories
    Path("working").mkdir(exist_ok=True)
    Path("logs").mkdir(exist_ok=True)
    Path("results").mkdir(exist_ok=True)

    # Check for existence of experiments directory
    experiments_dir = path.join(repo_path, config.get("experiments_path", "."))
    if not path.exists(experiments_dir):
        log.error(f"Experiment directory {experiments_dir} not found")
        return

    max_concurrency = config.get("max_concurrency", 1)
    tests = flatten_tests(config)

    # Initialize cloudlab driver
    username = config.get("username")
    if username is None:
        log.error("Cloudlab experiment username not specified")
        return
    profile = config.get("profile")
    if profile is None:
        log.error("Cloudlab experiment profile not specified")
        return

    # Load Cloudlab password
    if 'password_path' in config:
        password_path = config['password_path']
        try:
            with open(password_path, 'r') as password_file:
                password = password_file.read().strip()
        except IOError as ex:
            log.error(
                f"Could not load Cloudlab password file at {password_path}:")
            log.error(ex)
            return
    else:
        password = getpass.getpass(
            prompt=f'Cloudlab password for {username}: ')

    # Instantiate the driver
    headless = bool(config.get("headless"))
    global cloudlab
    log.info(
        f"Initializing {'headless' if headless else 'gui'} cloudlab driver for {username} with profile {profile}")
    cloudlab = Cloudlab(username, password, profile, headless)

    # Attempt to log in
    try:
        cloudlab_lock.acquire()
        log.info(f"Logging into cloudlab")
        cloudlab.login()
    except OperationFailed as ex:
        log.error("Could not log into cloudlab:")
        log.error(ex)
        log.error(traceback.format_exc())
        return
    except UnknownStateError as ex:
        log.error("Unknown state reached while logging into cloudlab driver:")
        log.error(ex)
        log.error(traceback.format_exc())
        return
    except Exception as ex:
        log.error("Encountered error while logging into cloudlab driver:")
        log.error(ex)
        log.error(traceback.format_exc())
        return
    else:
        log.info(f"Cloudlab login successful")
    finally:
        cloudlab_lock.release()

    # Use manual list to allow for rewinding in case of error
    i = -1
    while i < len(tests) - 1:
        i = i + 1

        while len(thread_queue) >= max_concurrency:
            thread_queue[0].join()
            thread_queue.pop(0)

        test = tests[i]
        log.info(f"Starting test {test.id()}")
        log.debug(test)

        test_experiment_dir = path.join(experiments_dir, test.experiment())
        if not path.exists(test_experiment_dir):
            log.error(
                f"Test experiment directory {test_experiment_dir} not found")
            continue

        config_sh_path = path.join(test_experiment_dir, "conf/config.sh")
        if not path.exists(config_sh_path):
            log.error(
                f"Test experiment config file {config_sh_path} not found")
            continue

        # Load test config
        test_config = ""
        with open(config_sh_path, "r") as config_file:
            test_config = config_file.read()

        # Provision experiment from cloudlab
        try:
            cloudlab_lock.acquire()
            log.info(f"Provisioning new experiment from cloudlab")
            experiment = cloudlab.provision()
        except OperationFailed as ex:
            log.error("Could not provision experiment on cloudlab:")
            log.error(ex)
            log.error(traceback.format_exc())
            continue
        except UnknownStateError as ex:
            log.error("Unknown state reached while logging into cloudlab driver:")
            log.error(ex)
            log.error(traceback.format_exc())
            continue
        except Exception as ex:
            log.error("Encountered error while logging into cloudlab driver:")
            log.error(ex)
            log.error(traceback.format_exc())
            continue
        else:
            log.info(
                f"Successfully provisioned new experiment from cloudlab: {experiment}")
        finally:
            cloudlab_lock.release()

        # Get hosts and then assign
        hosts = experiment.hostnames()
        executor_host = hosts[0]
        experiment_hosts = hosts[1:]

        def replace_host(match):
            return f'{match.group(1)}="{experiment_hosts.pop(0)}"'
        test_config = re.sub(HOST_CONFIG_REGEX, replace_host, test_config)

        # Then, replace overrides
        for (key, value) in test.options().items():
            key_regex = re.compile(f'(?m)^((?:readonly )?{key})="?.*"?$')

            def replace_value(match):
                if isinstance(value, str):
                    val = f'"{value}"'
                else:
                    val = str(value)
                return f'{match.group(1)}={val}'
            test_config = re.sub(key_regex, replace_value, test_config)

        # Create working directory
        work_dir = path.join("working", test.id())
        Path(work_dir).mkdir(parents=True, exist_ok=True)
        log.info(f"Using {work_dir} as the working directory")

        config_sh_path = path.join(work_dir, "config.sh")
        try:
            with open(config_sh_path, "w") as rendered_config_file:
                rendered_config_file.write(test_config)
            log.info(f"Wrote rendered config file to {config_sh_path}")
        except IOError as ex:
            log.error(f"Could not write rendered config to {config_sh_path}:")
            log.error(ex)
            log.warn(f"Restarting test")
            i = i - 1
            continue

        # Spawn thread to handle ssh/scp yielding
        log_path = path.join("logs", test.id() + ".log")
        results_path = path.join("results", test.id() + ".tar.gz")
        test_thread = TestExecutionThread(test, executor_host, config_sh_path,
                                          log_path, results_path, config, experiment)
        test_thread.start()
        thread_queue.append(test_thread)


def flatten_tests(config):
    """
    Flattens test replicas into a single list of Tests
    """

    tests = config.get("tests", [])
    global_options = config.get("options", {})
    flattened = []
    for test_set in tests:
        id = test_set["id"]
        experiment = test_set["experiment"]
        replicas = test_set.get("replicas", 1)
        completed = test_set.get("completed", 0)
        options = {**test_set.get("options", {}), **global_options}
        for i in range(replicas - completed):
            j = i + completed
            flattened.append(Test(f"{id}-{str(j)}", options, experiment))
    return flattened


def load_config(path):
    """
    Loads the config YAML file
    """

    config_dict = None
    try:
        with open(path, "r") as config_file:
            loader = yaml.Loader(config_file)
            config_dict = loader.get_data()
    except OSError as ex:
        log.error(f"An error ocurred during config file reading:")
        log.error(ex)
    except yaml.YAMLError as ex:
        log.error(f"An error ocurred during config YAML parsing:")
        log.error(ex)
    return config_dict


def find(data, path):
    """
    Gets an element in a deeply nested data structure
    """

    keys = path.split('.')
    rv = data
    for key in keys:
        if rv is None:
            return None
        else:
            rv = rv.get(key)
    return rv


def load_file(config, path):
    """
    Attempts to load the password from the config field
    """

    contents = None
    file_path = find(config, path)
    if file_path is not None:
        try:
            with open(file_path) as file_handle:
                contents = file_handle.read()
        except OSError as ex:
            log.error(f"An error ocurred during {path} file reading:")
            log.error(ex)
    return contents


def join_all():
    log.info("Joining threads")
    for thread in thread_queue:
        try:
            thread.join()
        except:
            pass


def join_then_quit():
    global stopping
    stopping = True
    term_cond.acquire()
    term_cond.notify_all()
    term_cond.release()
    join_all()
    log.info("Exiting")
    sys.exit(1)


def force_handler(signum, frame):
    join_then_quit()


def exit_gracefully(signum, frame):
    signal.signal(signal.SIGINT, force_handler)

    try:
        if input("\nReally quit? (y/n)>\n").lower().startswith('y'):
            join_then_quit()

    except KeyboardInterrupt:
        join_then_quit()

    # restore the exit gracefully handler here
    signal.signal(signal.SIGINT, exit_gracefully)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, exit_gracefully)
    main()
