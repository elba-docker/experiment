#!/bin/bash

# Load interference experiment to test the overhead of using rAdvisor
# to instrument running containers

# Load the current branch
git_branch=$(git branch --show-current)

# Change to the parent directory.
cd $(dirname "$(dirname "$(readlink -fm "$0")")")
echo "[$(date +%s)] CD: $(pwd)"

# Source configuration file.
source conf/config.sh

# All hosts involved
all_hosts="$CLIENT_HOSTS $WEB_HOSTS $POSTGRESQL_HOST $WORKER_HOSTS $MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# All hosts running Docker
docker_hosts="$MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# All hosts running Docker and getting instrumented with rAdvisor
container_instrumented_hosts="$MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# All hosts getting instrumented with collectl/milliscope
instrumented_hosts="$CLIENT_HOSTS $WEB_HOSTS $POSTGRESQL_HOST $WORKER_HOSTS $MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# All hosts that have the load interference task running in the background
# (NOTE: this does not include the $WEB_HOSTS, $POSTGRESQL_HOST, or $WORKER_HOSTS)
load_interference_hosts="$MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# Maps microservice container image names to the hosts they should be initialized on
declare -A microservice_hosts=(
  [blog]=$MICROBLOG_HOSTS
  [auth]=$AUTH_HOSTS
  [inbox]=$INBOX_HOSTS
  [queue]=$QUEUE_HOSTS
  [sub]=$SUB_HOSTS
)
# Maps microservice container image names to the ports they should be initialized with
declare -A microservice_ports=(
  [blog]=$MICROBLOG_PORT
  [auth]=$AUTH_PORT
  [inbox]=$INBOX_PORT
  [queue]=$QUEUE_PORT
  [sub]=$SUB_PORT
)
# Maps microservice container image names to the threadpool sizes they should be run with
declare -A microservice_threadpool_sizes=(
  [blog]=$MICROBLOG_THREADPOOLSIZE
  [auth]=$AUTH_THREADPOOLSIZE
  [inbox]=$INBOX_THREADPOOLSIZE
  [queue]=$QUEUE_THREADPOOLSIZE
  [sub]=$SUB_THREADPOOLSIZE
)
# Maps log names to their host lists, used for naming the final log archives
declare -A host_log_names=(
  [microblog]=$MICROBLOG_HOSTS
  [auth]=$AUTH_HOSTS
  [inbox]=$INBOX_HOSTS
  [queue]=$QUEUE_HOSTS
  [sub]=$SUB_HOSTS
  [db]=$POSTGRESQL_HOST
  [worker]=$WORKER_HOSTS
  [client]=$CLIENT_HOSTS
  [web]=$WEB_HOSTS
)


echo "[$(date +%s)] Socket setup:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Limiting socket backlog in host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
      BatchMode=yes $USERNAME@$host "
    sudo sysctl -w net.core.somaxconn=64
  "
done


echo "[$(date +%s)] Filesystem setup:"
if [[ $HOSTS_TYPE = "vm" ]]; then
  fs_rootdir="/experiment"
  for host in $all_hosts; do
    echo "  [$(date +%s)][VM] Creating directories in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        -o BatchMode=yes $USERNAME@$host "
      sudo mkdir -p $fs_rootdir
      sudo chown $USERNAME $fs_rootdir
    "
  done
else
  fs_rootdir="/mnt/experiment"
  pdisk="/dev/sdb"
  pno=1
  psize="128G"
  for host in $all_hosts; do
    echo "  [$(date +%s)][PHYSICAL] Creating disk partition in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        -o BatchMode=yes $USERNAME@$host "
      echo -e \"n\np\n${pno}\n\n+${psize}\nw\n\" | sudo fdisk $pdisk
      nohup sudo systemctl reboot -i &>/dev/null & exit
    "
  done
  sleep 240
  sessions=()
  n_sessions=0
  for host in $all_hosts; do
    echo "  [$(date +%s)][PHYSICAL] Making filesystem and mounting partition in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        -o BatchMode=yes $USERNAME@$host "
      sudo mkfs -F -t ext4 ${pdisk}${pno}
      sudo mkdir -p $fs_rootdir
      sudo mount ${pdisk}${pno} $fs_rootdir
      sudo chown $USERNAME $fs_rootdir
    " &
    sessions[$n_sessions]=$!
    let n_sessions=n_sessions+1
  done
  for session in ${sessions[*]}; do
    wait $session
  done
fi


echo "[$(date +%s)] Common software setup:"
wise_home="$fs_rootdir/wise-docker"
sessions=()
n_sessions=0
echo "[$(date +%s)] fs_rootdir: $fs_rootdir"
echo "[$(date +%s)] wise_home: $wise_home"
for host in $all_hosts; do
  echo "  [$(date +%s)] Setting up common software in host $host"

  # Set membership flags
  if [[ " $docker_hosts " =~ .*\ $host\ .* ]]; then is_docker=1; else is_docker=0; fi
  if [[ " $container_instrumented_hosts " =~ .*\ $host\ .* ]]; then is_docker_instrumented=1; else is_docker_instrumented=0; fi
  if [[ " $instrumented_hosts " =~ .*\ $host\ .* ]]; then is_instrumented=1; else is_instrumented=0; fi
  if [[ " $WEB_HOSTS " =~ .*\ $host\ .* ]]; then is_web=1; else is_web=0; fi
  echo "$host ; $is_docker ; $is_docker_instrumented ; $is_instrumented ; $is_web ;"

  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ~/.ssh/id_rsa $USERNAME@$host:.ssh
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
      BatchMode=yes $USERNAME@$host "
    # Synchronize apt.
    sudo apt-get update

    # Clone the experiment.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
    sudo rm -rf $wise_home
    sudo mkdir $wise_home
    sudo git clone --single-branch --branch \"$git_branch\" https://github.com/elba-docker/experiment.git $wise_home

    # Take ownership of the wise-home directory
    sudo chown -R $USERNAME $wise_home

    if [[ \"$is_docker\" -eq 1 ]]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn apt-key add -
      sudo add-apt-repository \\
        \"deb [arch=amd64] https://download.docker.com/linux/ubuntu \\
        \$(lsb_release -cs) \\
        stable\"
      sudo apt-get update

      # Install Docker CE.
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\
        containerd.io=1.2.10-3 \\
        docker-ce=5:19.03.4~3-0~ubuntu-\$(lsb_release -cs) \\
        docker-ce-cli=5:19.03.4~3-0~ubuntu-\$(lsb_release -cs)

      # Setup daemon.
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  \"exec-opts\": [\"native.cgroupdriver=systemd\"],
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"100m\"
  },
  \"storage-driver\": \"overlay2\"
}
EOF

      sudo mkdir -p /etc/systemd/system/docker.service.d
      # Restart docker.
      sudo systemctl daemon-reload
      sudo systemctl restart docker
    else
      # Install standard non-Docker software

      # Install Thrift
      echo \"[\$(date +%s)] Downloading packages for thrift 0.13.0 on $host\"
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y automake bison flex g++ git libboost-all-dev libevent-dev libssl-dev libtool make pkg-config > /dev/null 2>&1
      tar -xzf $wise_home/artifacts/thrift-0.13.0.tar.gz -C .
      cd thrift-0.13.0
      echo \"[\$(date +%s)] Installing thrift 0.13.0 on $host\"
      ./bootstrap.sh > /dev/null
      ./configure --without-python > /dev/null
      make > /dev/null 2>&1
      sudo make install > /dev/null

      # Set up Python 3 environment.
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y virtualenv
      sudo virtualenv -p `which python3` $wise_home/.env
    fi

    # Install the postgres client on the web server to use it to initialize the schema later
    if [[ \"$is_web\" -eq 1 ]]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-common
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-10
    fi

    if [[ \"$is_instrumented\" -eq 1 ]]; then
      # Install Collectl.
      if [[ \"$ENABLE_COLLECTL\" -eq 1 ]]; then
        cd $fs_rootdir
        sudo tar -xzf $wise_home/artifacts/collectl-4.3.1.src.tar.gz -C .
        cd collectl-4.3.1
        sudo ./INSTALL
      fi
    fi

    if [[ \"$is_docker_instrumented\" -eq 1 ]]; then
      if [[ \"$ENABLE_RADVISOR\" -eq 1 ]]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssl
      fi
    fi
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Database setup:"
sessions=()
n_sessions=0
for host in $POSTGRESQL_HOST; do
  echo "  [$(date +%s)] Setting up database server on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-10
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-common
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-10

    export POSTGRES_MAXCONNECTIONS=\"$POSTGRES_MAXCONNECTIONS\"

    $wise_home/microblog_bench/postgres/scripts/start_postgres.sh
    sudo -u postgres psql -c \"CREATE ROLE $USERNAME WITH LOGIN CREATEDB SUPERUSER\"
    createdb microblog_bench
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


# Piggy back off of client machine(s) to run all of the database initialization scripts
echo "[$(date +%s)] Database schema setup:"
sessions=()
n_sessions=0
for host in $WEB_HOSTS; do
  echo "  [$(date +%s)] Setting up database schema using host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
      # auth microservice schema
      $wise_home/WISEServices/auth/scripts/setup_database.sh $POSTGRESQL_HOST
      # inbox microservice schema
      $wise_home/WISEServices/inbox/scripts/setup_database.sh $POSTGRESQL_HOST
      # queue microservice schema
      $wise_home/WISEServices/queue_/scripts/setup_database.sh $POSTGRESQL_HOST
      # subscription microservice schema
      $wise_home/WISEServices/sub/scripts/setup_database.sh $POSTGRESQL_HOST
      # microblog microservice schema
      $wise_home/microblog_bench/services/microblog/scripts/setup_database.sh $POSTGRESQL_HOST
  " &
  # Only execute for the first web host
  wait $!
  break
done


echo "[$(date +%s)] Initializing containerized microservices:"
sessions=()
n_sessions=0
for K in "${!microservice_hosts[@]}"; do
  hosts=${microservice_hosts[$K]}
  port=${microservice_ports[$K]}
  threadpool_size=${microservice_threadpool_sizes[$K]}
  image="$K"
  echo "  [$(date +%s)] Setting up microservice class \"$K\""
  for host in $hosts; do
    echo "    [$(date +%s)] Setting up microservice class \"$K\" on host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        -o BatchMode=yes $USERNAME@$host "
        sudo docker run -d -p ${port}:${port} wisebenchmark/${image}:v1.0 $port $threadpool_size $POSTGRESQL_HOST $USERNAME
    " &
    sessions[$n_sessions]=$!
    let n_sessions=n_sessions+1
  done
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Web setup:"
sessions=()
n_sessions=0
for host in $WEB_HOSTS; do
  echo "  [$(date +%s)] Setting up web server on host $host"

  APACHE_WSGIDIRPATH=$wise_home/microblog_bench/web/src
  APACHE_PYTHONPATH=$wise_home/WISEServices/auth/include/py/
  APACHE_PYTHONPATH=$wise_home/WISEServices/inbox/include/py/:$APACHE_PYTHONPATH
  APACHE_PYTHONPATH=$wise_home/WISEServices/queue_/include/py/:$APACHE_PYTHONPATH
  APACHE_PYTHONPATH=$wise_home/WISEServices/sub/include/py/:$APACHE_PYTHONPATH
  APACHE_PYTHONPATH=$wise_home/microblog_bench/services/microblog/include/py/:$APACHE_PYTHONPATH
  APACHE_PYTHONHOME=$wise_home/.env
  APACHE_WSGIDIRPATH=${APACHE_WSGIDIRPATH//\//\\\\\/}
  APACHE_PYTHONPATH=${APACHE_PYTHONPATH//\//\\\\\/}
  APACHE_PYTHONHOME=${APACHE_PYTHONHOME//\//\\\\\/}

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Install Apache/mod_wsgi.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apache2
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apache2-dev
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        libapache2-mod-wsgi-py3

    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    # Take ownership of the virtual environment
    sudo chown -R $USERNAME $wise_home/.env
    pip install flask
    pip install flask_httpauth
    pip install pyyaml
    pip install thrift
    deactivate

    # Generate Thrift code.
    $wise_home/WISEServices/auth/scripts/gen_code.sh py
    $wise_home/WISEServices/inbox/scripts/gen_code.sh py
    $wise_home/WISEServices/queue_/scripts/gen_code.sh py
    $wise_home/WISEServices/sub/scripts/gen_code.sh py
    $wise_home/microblog_bench/services/microblog/scripts/gen_code.sh py

    # Export configuration parameters.
    export APACHE_WSGIDIRPATH=\"$APACHE_WSGIDIRPATH\"
    export APACHE_PYTHONPATH=\"$APACHE_PYTHONPATH\"
    export APACHE_PYTHONHOME=\"$APACHE_PYTHONHOME\"
    export APACHE_PROCESSES=$APACHE_PROCESSES
    export APACHE_THREADSPERPROCESS=$APACHE_THREADSPERPROCESS
    export APACHE_WSGIFILENAME=web.wsgi
    export AUTH_HOSTS=$AUTH_HOSTS
    export AUTH_PORT=$AUTH_PORT
    export INBOX_HOSTS=$INBOX_HOSTS
    export INBOX_PORT=$INBOX_PORT
    export MICROBLOG_HOSTS=$MICROBLOG_HOSTS
    export MICROBLOG_PORT=$MICROBLOG_PORT
    export QUEUE_HOSTS=$QUEUE_HOSTS
    export QUEUE_PORT=$QUEUE_PORT
    export SUB_HOSTS=$SUB_HOSTS
    export SUB_PORT=$SUB_PORT

    $wise_home/microblog_bench/web/scripts/start_server.sh apache
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Worker setup:"
sessions=()
n_sessions=0
for host in $WORKER_HOSTS; do
  echo "  [$(date +%s)] Setting up worker on host $host"

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    # Take ownership of the virtual environment
    sudo chown -R $USERNAME $wise_home/.env
    pip install pyyaml
    pip install thrift

    # Generate Thrift code.
    $wise_home/WISEServices/inbox/scripts/gen_code.sh py
    $wise_home/WISEServices/queue_/scripts/gen_code.sh py
    $wise_home/WISEServices/sub/scripts/gen_code.sh py

    # Export configuration parameters.
    export NUM_WORKERS=$NUM_WORKERS
    export INBOX_HOSTS=$INBOX_HOSTS
    export INBOX_PORT=$INBOX_PORT
    export QUEUE_HOSTS=$QUEUE_HOSTS
    export QUEUE_PORT=$QUEUE_PORT
    export SUB_HOSTS=$SUB_HOSTS
    export SUB_PORT=$SUB_PORT
    export WISE_HOME=$wise_home
    export WISE_DEBUG=$WISE_DEBUG

    $wise_home/microblog_bench/worker/scripts/start_workers.sh
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Client setup:"
# Create the workload file render pattern (passed to sed) from the map
declare -A workload_variables=(
  [WISEHOME]=$wise_home
  [NUMBER_SESSIONS]=$AUTH_HOSTS
  # formula for the total time
  [TOTAL_TIME]=$(((4 * $T_BUFFER) + (2 * $T_RAMP) + $T_NO_INTERFERENCE + $T_INTERFERENCE))
  [RAMP_UP]=$T_RAMP
  [RAMP_DOWN]=$T_RAMP
)
variable_substitutions=""
for K in "${!workload_variables[@]}"; do
  variable_substitutions="$K='${workload_variables[$K]}' ${variable_substitutions}"
done
# Perform the remote SSH execution
sessions=()
n_sessions=0
for host in $CLIENT_HOSTS; do
  echo "  [$(date +%s)] Setting up client on host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $WORKLOAD_CONFIG $USERNAME@$host:$wise_home/experiments/load_interference/conf
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SESSION_CONFIG $USERNAME@$host:$wise_home/experiments/load_interference/conf
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    # Take ownership of the virtual environment
    sudo chown -R $USERNAME $wise_home/.env
    pip install click
    pip install requests
    pip install pyyaml
    deactivate

    # Render workload.yml (WORKLOAD_CONFIG).
    $variable_substitutions envsubst < $wise_home/experiments/load_interference/$WORKLOAD_CONFIG | tee $wise_home/experiments/load_interference/$WORKLOAD_CONFIG
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Processor setup:"
sessions=()
n_sessions=0
if [[ $HOSTS_TYPE = "physical" ]]; then
  if [[ $HARDWARE_TYPE = "c8220" ]]; then
  for host in $all_hosts; do
    echo "  [$(date +%s)] Disabling cores in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
        BatchMode=yes $USERNAME@$host "
      for i in \$(seq $ENABLED_CPUS 39); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
    " &
    sessions[$n_sessions]=$!
    let n_sessions=n_sessions+1
  done
  fi
  if [[ $HARDWARE_TYPE = "d430" ]]; then
  for host in $all_hosts; do
    echo "  [$(date +%s)] Disabling cores in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
        BatchMode=yes $USERNAME@$host "
      for i in \$(seq $ENABLED_CPUS 31); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
    " &
    sessions[$n_sessions]=$!
    let n_sessions=n_sessions+1
  done
  fi
fi
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] System instrumentation:"
sessions=()
n_sessions=0
radvisor_stats=$wise_home/radvisor/out
for host in $all_hosts; do
  echo "  [$(date +%s)] Instrumenting host $host"

  # Set membership flags
  if [[ " $container_instrumented_hosts " =~ .*\ $host\ .* ]]; then is_docker_instrumented=1; else is_docker_instrumented=0; fi
  if [[ " $instrumented_hosts " =~ .*\ $host\ .* ]]; then is_instrumented=1; else is_instrumented=0; fi

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    cd $wise_home

    if [[ \"$is_instrumented\" -eq 1 ]]; then
      # Activate WISETrace.
      cd $wise_home/WISETrace/kernel_modules/connect
      make
      sudo insmod spec_connect.ko
      cd $wise_home/WISETrace/kernel_modules/sendto
      make
      sudo insmod spec_sendto.ko
      cd $wise_home/WISETrace/kernel_modules/recvfrom
      make
      sudo insmod spec_recvfrom.ko
      cd $wise_home

      # Only activate collectl if enabled
      if [[ \"$ENABLE_COLLECTL\" -eq 1 ]]; then
        mkdir -p collectl/data
        nohup sudo nice -n -1 /usr/bin/collectl -sCDmnt -i.05 -oTm -P -f collectl/data/coll > /dev/null 2>&1 &
      fi
    fi

    # Only activate rAdvisor if enabled
    if [[ \"$is_docker_instrumented\" -eq 1 ]]; then
      if [[ \"$ENABLE_RADVISOR\" -eq 1 ]]; then
        mkdir -p $radvisor_stats
        chmod +x ./artifacts/radvisor
        nohup sudo nice -n -1 ./artifacts/radvisor run docker -d $radvisor_stats -p $POLLING_INTERVAL -i ${COLLECTION_INTERVAL}ms --quiet > /dev/null 2>&1 &
      fi
    fi
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


sleep 16


echo "[$(date +%s)] Calculating experiment schedule:"
# Here we determine when to start the experiment,
# and when to start the load interference part
current_ts=$(date +%s%3N)
# Start after 20 more seconds
start_ts=$(($current_ts + (20 * 1000) ))
# Start the no-interference collection after ramping up & going through a buffer interval
no_interference_recording_ts=$(($start_ts + ($T_RAMP + $T_BUFFER) * 1000))
# start the interference after the end of the no-interference interval and an additional buffer
interference_start_ts=$(($no_interference_start_ts + ($T_NO_INTERFERENCE + $T_BUFFER) * 1000))
# start recording during the interference interval after an additional buffer interval
interference_recording_ts=$(($interference_recording_ts + ($T_BUFFER) * 1000))
interference_duration_seconds=$(($T_INTERFERENCE + (2 * $T_BUFFER) ))
echo "  Start: $start_ts"
echo "  Beginning of no-interference recording: $no_interference_recording_ts"
echo "  End of no-interference recording: $(($no_interference_recording_ts + ($T_NO_INTERFERENCE) * 1000))"
echo "  Beginning of interference load: $interference_start_ts"
echo "  Beginning of interference recording: $interference_recording_ts"
echo "  End of interference recording: $(($no_interference_recording_ts + ($T_INTERFERENCE) * 1000))"
echo "  End of interference load: $(($no_interference_recording_ts + ($T_INTERFERENCE + $T_BUFFER) * 1000))"
echo "  End: $(($no_interference_recording_ts + ($T_INTERFERENCE + $T_BUFFER + $T_RAMP) * 1000))"


echo "[$(date +%s)] Benchmark execution:"
sessions=()
n_sessions=0
for host in $CLIENT_HOSTS; do
  echo "  [$(date +%s)] Generating requests from host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    source $wise_home/.env/bin/activate

    # Set PYTHONPATH.
    export PYTHONPATH=$wise_home/WISELoad/include/:$PYTHONPATH

    # Export configuration parameters.
    export WISE_DEBUG=$WISE_DEBUG

    # Load balance.
    mkdir -p $wise_home/logs
    # Sleep until the start
    current_ts=\$(date +%s%3N)
    difference=\$(($start_ts - \$current_ts))
    sleep \$(echo \"\$difference / 1000\" | bc -l)
    python $wise_home/microblog_bench/client/session.py --config $wise_home/experiments/load_interference/$WORKLOAD_CONFIG --hostname $WEB_HOSTS --port 80 --prefix microblog
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for host in $load_interference_hosts; do
  echo "  [$(date +%s)] Preparing to execute load interference task in $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Sleep until the start of load interference
    current_ts=\$(date +%s%3N)
    difference=\$(($interference_start_ts - \$current_ts))
    sleep \$(echo \"\$difference / 1000\" | bc -l)
    # Run docker containers (in parallel)
    for i in {1..$NUM_CONTAINERS}
    do
        sudo docker run --cpus $CPU_PER_STRESS_CONTAINER -d --memory $MEM_PER_STRESS_CONTAINER jazevedo6/load_interference:v1.0 bash -c \"
            stress --cpu $NUM_CPU_STRESSORS --vm $NUM_MEM_STRESSORS --vm-bytes 128M --timeout ${interference_duration_seconds}s
        \" &
    done
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Cleanup:"
sessions=()
n_sessions=0
# <https://github.com/elba-docker/moby/blob/277079e650c835624a303ed3de4f90d0f6db5814/daemon/stats.go#L51>
patched_moby_logs="/var/logs/docker/stats"
for K in "${!host_log_names[@]}"; do
  log_name="$K"
  hosts=${host_log_names[$K]}
  echo "  [$(date +%s)] Cleaning up host class \"$K\""
  for host in $hosts; do
    echo "    [$(date +%s)] Cleaning up host class \"$K\" on $host"

    # Set membership flags
    if [[ " $docker_hosts " =~ .*\ $host\ .* ]]; then is_docker=1; else is_docker=0; fi
    if [[ " $container_instrumented_hosts " =~ .*\ $host\ .* ]]; then is_docker_instrumented=1; else is_docker_instrumented=0; fi
    if [[ " $instrumented_hosts " =~ .*\ $host\ .* ]]; then is_instrumented=1; else is_instrumented=0; fi
    if [[ " $WEB_HOSTS " =~ .*\ $host\ .* ]]; then is_web=1; else is_web=0; fi

    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        -o BatchMode=yes $USERNAME@$host "
        if [[ \"$is_docker\" -eq 1 ]]; then
          # Stop and remove all docker containers
          sudo docker stop \$(sudo docker ps -aq)
          sudo docker rm \$(sudo docker ps -aq)
          sleep 4s
        fi

        if [[ \"$is_instrumented\" -eq 1 ]]; then
          # Stop resource monitors.
          if [[ \"$ENABLE_COLLECTL\" -eq 1 ]]; then
            sudo pkill collectl
          fi
          sleep 4s
        fi

        if [[ \"$is_docker_instrumented\" -eq 1 ]]; then
          if [[ \"$ENABLE_RADVISOR\" -eq 1 ]]; then
            sudo pkill radvisor
          fi
          sleep 4s
        fi

        # Collect log data.
        mkdir -p logs
        if [[ \"$is_instrumented\" -eq 1 ]]; then
          if [[ \"$ENABLE_COLLECTL\" -eq 1 ]]; then
            mkdir -p logs/collectl
            mv $wise_home/collectl/data/coll-* logs/collectl
          fi

          mkdir -p logs/milliscope
          cat /proc/spec_connect > logs/milliscope/spec_connect.csv
          cat /proc/spec_sendto > logs/milliscope/spec_sendto.csv
          cat /proc/spec_recvfrom > logs/milliscope/spec_recvfrom.csv
        fi

        if [[ \"$is_docker_instrumented\" -eq 1 ]]; then
          if [[ \"$ENABLE_RADVISOR\" -eq 1 ]]; then
            mkdir -p logs/radvisor
            mv $radvisor_stats/*.log logs/radvisor
          fi
        fi

        tar -C logs -czf log-${log_name}-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

        if [[ \"$is_instrumented\" -eq 1 ]]; then
          # Stop event monitors.
          sudo rmmod spec_connect
          sudo rmmod spec_sendto
          sudo rmmod spec_recvfrom
        fi
    " &
    sessions[$n_sessions]=$!
    let n_sessions=n_sessions+1
  done
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Log data collection:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Collecting log data from host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $USERNAME@$host:log-*.tar.gz .
done
tar -czf results.tar.gz log-*.tar.gz conf/
