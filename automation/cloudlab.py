import re
import time
import json
import urllib
import traceback
from log import log
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.support import expected_conditions
from selenium.webdriver.support.wait import WebDriverWait
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.desired_capabilities import DesiredCapabilities
from selenium.common.exceptions import TimeoutException, NoSuchElementException

NOT_ENOUGH_REGEX = re.compile(
    r'[0-9]+ nodes of type .+ requested, but only [0-9]+ available nodes of type .+ found')
SSH_REGEX = re.compile(r'ssh -p [0-9]+ \S+@(\S+)')


class UnknownStateError(Exception):
    pass


class OperationFailed(Exception):
    pass


class ProvisionedExperiment():
    def __init__(self, uuid, name):
        self._uuid = uuid
        self._name = name

    def uuid(self):
        return self._uuid

    def name(self):
        return self._name

    def __repr__(self):
        return f"{self._name} ({self._uuid})"


class Experiment(ProvisionedExperiment):
    def __init__(self, uuid, name, hostnames):
        ProvisionedExperiment.__init__(self, uuid, name)
        self._hostnames = hostnames

    def hostnames(self):
        return self._hostnames


class Cloudlab():
    def __init__(self, username, password, profile, headless):
        options = Options()
        options.headless = headless
        options.add_argument("window-size=1920,1080")
        self._driver = webdriver.Chrome(chrome_options=options)
        self._driver.implicitly_wait(0.35)
        self._username = username
        self._password = password
        self._authenticated = False
        self._profile = profile

    def login(self, retry_count=5):
        driver = self._driver

        for i in range(retry_count):
            is_last = i >= retry_count - 1
            trying_again_suffix = "trying again" if not is_last else ""

            driver.get("https://www.cloudlab.us/login.php")
            WebDriverWait(driver, 15).until(lambda driver: driver.execute_script(
                'return document.readyState') == 'complete')

            if 'User Dashboard' in driver.title:
                self._authenticated = True
                return
            elif 'Login' in driver.title:
                self._authenticated = False
            else:
                raise UnknownStateError(
                    f'Unknown page reached "{driver.title}" @ {driver.current_url}"')

            driver.find_element(By.NAME, "uid").click()
            driver.find_element(By.NAME, "uid").send_keys(self._username)
            driver.find_element(By.NAME, "password").send_keys(self._password)
            driver.find_element(By.NAME, "login").click()

            WebDriverWait(driver, 60).until(lambda driver: driver.execute_script(
                'return document.readyState') == 'complete')

            if 'User Dashboard' in driver.title:
                self._authenticated = True
                return
            elif 'Login' in driver.title:
                log.warning(f"Login was unsuccessful.{trying_again_suffix}")
                pass
            else:
                raise UnknownStateError(
                    f'Unknown page reached "{driver.title}" @ {driver.current_url}"')

        # Check if last run succeeded
        if 'User Dashboard' in driver.title:
            self._authenticated = True
            return

        raise OperationFailed("Could not log into CloudLab")

    def terminate(self, experiment, retry_count=5):
        driver = self._driver

        for i in range(retry_count):
            is_last = i >= retry_count - 1
            trying_again_suffix = "trying again after 1 minute" if not is_last else ""

            if not self._authenticated:
                self.login(retry_count=retry_count)

            driver.get(
                f"https://www.cloudlab.us/status.php?uuid={experiment.uuid()}")
            WebDriverWait(driver, 60).until(lambda driver: driver.execute_script(
                'return document.readyState') == 'complete')
            # Make sure we're authenticated
            if 'Login' in driver.title:
                self._authenticated = False
                self.login(retry_count=retry_count)

            # Expand header if collapsed
            try:
                WebDriverWait(driver, 15).until(expected_conditions.visibility_of_element_located(
                    (By.ID, "terminate_button")))
            except (NoSuchElementException, TimeoutException):
                WebDriverWait(driver, 15).until(expected_conditions.presence_of_element_located(
                    (By.XPATH, "//a[@id='profile_status_toggle']")))
                driver.find_element(
                    By.XPATH, "//a[@id='profile_status_toggle']").click()
                WebDriverWait(driver, 15).until(expected_conditions.visibility_of_element_located(
                    (By.ID, "terminate_button")))
                try:
                    term_button = driver.find_element_by_id("terminate_button")
                except NoSuchElementException as ex:
                    log.warning(
                        f"Terminate button could not be found even after expanding;{trying_again_suffix}")
                    log.warning(ex)
                    if not is_last:
                        time.sleep(60)
                    continue

            try:
                # Click terminate and confirm
                WebDriverWait(driver, 240).until(expected_conditions.element_to_be_clickable(
                    (By.ID, "terminate_button")))
                term_button = driver.find_element_by_id("terminate_button")
                term_button.click()
                WebDriverWait(driver, 4).until(expected_conditions.element_to_be_clickable(
                    (By.CSS_SELECTOR, "#terminate_modal #terminate")))
                driver.find_element_by_css_selector(
                    "#terminate_modal #terminate").click()
            except TimeoutError:
                log.warning(
                    f"Could not wait on terminate pathway to become clickable; Clearing{trying_again_suffix}")
                if not is_last:
                    time.sleep(60)
            else:
                log.info(f"Terminated experiment {experiment}")
                return

        raise OperationFailed(
            f"Could not terminate experiment {experiment} on Cloudlab")

    def safe_terminate(self, experiment, retry_count=5):
        try:
            self.terminate(experiment, retry_count)
        except Exception as ex:
            log.warning(
                f"An exception ocurred while attempting to terminate {experiment}:")
            log.warning(ex)
            log.warning(traceback.format_exc())

    def provision(self, name=None, expires_in=5, retry_count=5):
        driver = self._driver

        for i in range(retry_count):
            is_last = i >= retry_count - 1
            trying_again_suffix = " and trying again" if not is_last else ""

            if not self._authenticated:
                self.login(retry_count=retry_count)

            driver.get("https://www.cloudlab.us/instantiate.php")
            WebDriverWait(driver, 60).until(lambda driver: driver.execute_script(
                'return document.readyState') == 'complete')
            # Make sure we're authenticated
            if "Login" in driver.title:
                self._authenticated = False
                self.login(retry_count=retry_count)

            try:
                WebDriverWait(driver, 15).until(expected_conditions.element_to_be_clickable(
                    (By.ID, "change-profile")))
                driver.find_element(By.ID, "change-profile").click()
                # Wait for page to select initial profile (otherwise the selection will be cleared)
                WebDriverWait(driver, 15).until(expected_conditions.presence_of_element_located(
                    (By.CSS_SELECTOR, "li.profile-item.selected")))
                driver.find_element(
                    By.XPATH, f"//li[@name='{self._profile}']").click()
                WebDriverWait(driver, 15).until(expected_conditions.presence_of_element_located(
                    (By.XPATH, f"//li[@name='{self._profile}' and contains(@class, 'selected')]")))
                driver.find_element(
                    By.XPATH, "//button[contains(text(),'Select Profile')]").click()
                WebDriverWait(driver, 30).until(expected_conditions.element_to_be_clickable(
                    (By.LINK_TEXT, "Next")))
                driver.find_element(By.LINK_TEXT, "Next").click()

                # Set name if given
                if name is not None:
                    driver.find_element(By.ID, "experiment_name").click()
                    driver.find_element(
                        By.ID, "experiment_name").send_keys(name)

                WebDriverWait(driver, 15).until(expected_conditions.element_to_be_clickable(
                    (By.LINK_TEXT, "Next")))
                driver.find_element(By.LINK_TEXT, "Next").click()
                WebDriverWait(driver, 15).until(expected_conditions.element_to_be_clickable(
                    (By.ID, "experiment_duration")))
                driver.find_element(By.ID, "experiment_duration").click()
                driver.find_element(By.ID, "experiment_duration").clear()
                driver.find_element(
                    By.ID, "experiment_duration").send_keys(str(expires_in))
                WebDriverWait(driver, 15).until(expected_conditions.element_to_be_clickable(
                    (By.LINK_TEXT, "Finish")))
                driver.find_element(By.LINK_TEXT, "Finish").click()
            except (TimeoutException, NoSuchElementException) as ex:
                raise OperationFailed(
                    f"Could not provision experiment with name {name}", ex)

            try:
                # Wait until the info page has been loaded
                WebDriverWait(driver, 60).until(
                    expected_conditions.title_contains("Experiment Status"))
                WebDriverWait(driver, 60).until(lambda driver: driver.execute_script(
                    'return document.readyState') == 'complete')
            except TimeoutException:
                # Can't really clean up if an error ocurrs here, so hope it doesn't
                if 'Login' in driver.title:
                    log.warning(f"Logged out! Logging in{trying_again_suffix}")
                    self._authenticated = False
                    continue
                elif 'Instantiate' in driver.title:
                    log.error(
                        f"Still on instantiate page after wait! Stopping{trying_again_suffix}")
                    continue
                else:
                    raise UnknownStateError(
                        f'Unknown page reached "{driver.title}" @ {driver.current_url}"')

            # Consider the experiment provisioned here, so any failures from here on need
            # to be cleaned up (experiment terminated)
            WebDriverWait(driver, 60).until(expected_conditions.presence_of_element_located(
                (By.XPATH,  "//td[contains(.,'Name:')]/following-sibling::td")))
            exp_name = driver.find_element_by_xpath(
                "//td[contains(.,'Name:')]/following-sibling::td").text
            url_parts = urllib.parse.urlparse(driver.current_url)
            uuid = urllib.parse.parse_qs(url_parts.query).get("uuid")[0]
            experiment = ProvisionedExperiment(uuid, exp_name)
            log.info(f"Instantiating experiment {experiment}")

            # Wait on status until "ready" or something else
            status_xpath = "//span[@id='quickvm_status']"
            status = driver.find_element_by_xpath(status_xpath).text
            if status != "ready":
                log.debug(f"Waiting for experiment to become ready")

            while status != "ready":
                try:
                    WebDriverWait(driver, 4).until(
                        expected_conditions.text_to_be_present_in_element((By.XPATH, status_xpath), "ready"))
                except TimeoutException:
                    status = driver.find_element_by_xpath(status_xpath).text
                    if status == "terminating":
                        # Already terminating; back off for 5 minutes and try again
                        log.warning(
                            f"Experiment is marked as terminating: backing off for 5 minutes{trying_again_suffix}! {self.get_error_text()}")
                        if not is_last:
                            time.sleep(5 * 60)
                        break
                    elif status == "ready":
                        break
                    elif status == 'created' or status == 'provisioning' or status == 'booting':
                        # Good; keep waiting
                        continue
                    else:
                        # If "failed" or otherwise, assume failure; need to clean up
                        # Try to extract error
                        cloudlab_error = self.get_error_text()
                        log.error(
                            f"Experiment is marked as {status}: stopping{trying_again_suffix}! {self.get_error_text()}")
                        self.safe_terminate(
                            experiment, retry_count=retry_count)
                        if not is_last:
                            backoff_f = 5 * (1 + float(i) / 2)
                            backoff = '{:.1f}'.format(backoff_f)
                            if "Resource reservation violation" in cloudlab_error:
                                log.warning(
                                    f"Resource reservation violation: backing off for {backoff} minutes before retrying")
                            elif re.search(NOT_ENOUGH_REGEX, cloudlab_error):
                                log.warning(
                                    f"Insufficient nodes available: backing off for {backoff} minutes before retrying")
                            else:
                                log.warning(
                                    f"Error in provisioning; backing off for {backoff} minutes before retrying")
                            time.sleep(backoff_f * 60)
                        break
                else:
                    status = "ready"
                    break

            if status != "ready":
                continue

            try:
                # Navigate to list panel
                WebDriverWait(driver, 15).until(
                    expected_conditions.visibility_of_element_located((By.ID, "show_listview_tab")))
                driver.find_element(By.ID, "show_listview_tab").click()
            except (TimeoutException, NoSuchElementException) as ex:
                log.error(
                    f"An error ocurred while attempting to expand the experiment listview!")
                log.error(ex)
                log.warning(
                    f"Terminating{trying_again_suffix}! {self.get_error_text()}")
                self.safe_terminate(experiment, retry_count=retry_count)
                continue

            # Should be ready here, read hostnames
            ssh_commands = [elem.text for elem in driver.find_elements_by_xpath(
                "//td[@name='sshurl']//kbd")]
            if len(ssh_commands) == 0:
                log.warning(
                    f"Hostnames list was empty by the end of the provisioning process! Terminating{trying_again_suffix}! {self.get_error_text()}")
                self.safe_terminate(experiment, retry_count=retry_count)
                continue
            hostnames = []
            for ssh_command in ssh_commands:
                match_obj = re.search(SSH_REGEX, ssh_command)
                if match_obj:
                    hostnames.append(match_obj.group(1))

            # Experiment successfully provisioned, hostnames extracted
            return Experiment(experiment.uuid(), experiment.name(), hostnames)

        raise OperationFailed(
            f"Could not provision experiment {f'with name {name} ' if name is not None else ''}on Cloudlab")

    def try_extract_error(self):
        driver = self._driver
        top_status = driver.find_element_by_id("status_message").text
        if top_status == "Something went wrong!":
            try:
                WebDriverWait(driver, 15).until(
                    expected_conditions.visibility_of_element_located((By.ID, "error_panel")))
            except TimeoutException:
                return None
            error_text_elem = driver.find_element_by_id("error_panel_text")
            if error_text_elem is not None:
                return error_text_elem.text
        return None

    def get_error_text(self):
        error = self.try_extract_error()
        return f"(Cloudlab error:\n{error})" if error is not None else ""
