#!/bin/bash

# Indirect overhead measurement via a microservice application benchmark, Wise

# Change to the parent directory.
cd $(dirname "$(dirname "$(readlink -fm "$0")")")
echo "[$(date +%s)] CD: $(pwd)"

# Source configuration file.
source conf/config.sh

# All hosts involved
all_hosts="$CLIENT_HOSTS $WEB_HOSTS $POSTGRESQL_HOST $WORKER_HOSTS $MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# All hosts running Docker
docker_hosts="$MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# All hosts running Docker and getting instrumented with rAdvisor/moby
container_instrumented_hosts="$MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
# All hosts getting instrumented with collectl/milliscope
instrumented_hosts="$CLIENT_HOSTS $WEB_HOSTS $POSTGRESQL_HOST $WORKER_HOSTS $MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
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
wise_home="$fs_rootdir/wise-kubernetes"
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

    # Clone wise-kubernetes.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
    sudo rm -rf $wise_home
    sudo mkdir $wise_home
    sudo git clone https://github.com/elba-kubernetes/experiment.git $wise_home

    if [[ \"$is_docker\" -eq 1 ]]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn apt-key add -
      sudo add-apt-repository \\
        \"deb [arch=amd64] https://download.docker.com/linux/ubuntu \\
        \$(lsb_release -cs) \\
        stable\"
      sudo apt-get update

      # Install Docker.
      if [[ \"$USE_PATCHED_DOCKER\" -eq 1 ]]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\
          containerd.io \\
          $wise_home/artifacts/docker-ce_19.03.8~elba~3-0~ubuntu-bionic_amd64.deb \\
          $wise_home/artifacts/docker-ce-cli_19.03.8~elba~3-0~ubuntu-bionic_amd64.deb
      else
        ## Install Docker CE.
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\
          containerd.io=1.2.10-3 \\
          docker-ce=5:19.03.4~3-0~ubuntu-\$(lsb_release -cs) \\
          docker-ce-cli=5:19.03.4~3-0~ubuntu-\$(lsb_release -cs)
      fi
      
      # Setup daemon.
      if [[ \"$USE_PATCHED_DOCKER\" -eq 1 ]] && [[ \"$instrumented_hosts\" -eq 1 ]]; then
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  \"exec-opts\": [\"native.cgroupdriver=systemd\"],
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"100m\"
  },
  \"storage-driver\": \"overlay2\",
  \"stats-interval\": $COLLECTION_INTERVAL
}
EOF
      else
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
      fi

      sudo mkdir -p /etc/systemd/system/docker.service.d
      # Restart docker.
      sudo systemctl daemon-reload
      sudo systemctl restart docker
    else 
      # Install standard non-Docker software
      # Install Thrift
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y automake bison flex g++ git libboost-all-dev libevent-dev libssl-dev libtool make pkg-config
      tar -xzf $wise_home/artifacts/thrift-0.13.0.tar.gz -C .
      cd thrift-0.13.0
      ./bootstrap.sh
      ./configure --without-python
      make > /dev/null 2>&1
      sudo make install > /dev/null 2>&1

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

    export POSTGRES_MAXCONNECTIONS="$POSTGRES_MAXCONNECTIONS"

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
      sudo $wise_home/WISEServices/auth/scripts/setup_database.sh $POSTGRESQL_HOST
      # inbox microservice schema
      sudo $wise_home/WISEServices/inbox/scripts/setup_database.sh $POSTGRESQL_HOST
      # queue microservice schema
      sudo $wise_home/WISEServices/queue_/scripts/setup_database.sh $POSTGRESQL_HOST
      # subscription microservice schema
      sudo $wise_home/WISEServices/sub/scripts/setup_database.sh $POSTGRESQL_HOST
      # microblog microservice schema
      sudo $wise_home/microblog_bench/services/microblog/scripts/setup_database.sh $POSTGRESQL_HOST
  " &
  # Only execute for the first web host
  wait $!
  break
done


echo "[$(date +%s)] Initializing containerized microservices:"
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
        sudo docker run -d -p ${port}:${port} harvardbiodept/${image}:v1.0 $port $threadpool_size $POSTGRESQL_HOST
    " &
    wait $!
  done
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
    export APACHE_WSGIDIRPATH="$APACHE_WSGIDIRPATH"
    export APACHE_PYTHONPATH="$APACHE_PYTHONPATH"
    export APACHE_PYTHONHOME="$APACHE_PYTHONHOME"
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
sessions=()
n_sessions=0
for host in $CLIENT_HOSTS; do
  echo "  [$(date +%s)] Setting up client on host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no conf/workload.yml $USERNAME@$host:$wise_home/experiments/indirect_response_time/conf
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no conf/session.yml $USERNAME@$host:$wise_home/experiments/indirect_response_time/conf
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    pip install click
    pip install requests
    pip install pyyaml
    deactivate

    # Render workload.yml.
    WISEHOME=${wise_home//\//\\\\\/}
    sed -i \"s/{{WISEHOME}}/\$WISEHOME/g\" $wise_home/experiments/indirect_response_time/conf/workload.yml
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Processor setup:"
if [[ $HOSTS_TYPE = "physical" ]]; then
  if [[ $HARDWARE_TYPE = "c8220" ]]; then
  for host in $all_hosts; do
    echo "  [$(date +%s)] Disabling cores in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
        BatchMode=yes $USERNAME@$host "
      for i in \$(seq $ENABLED_CPUS 39); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
    "
  done
  fi
  if [[ $HARDWARE_TYPE = "d430" ]]; then
  for host in $all_hosts; do
    echo "  [$(date +%s)] Disabling cores in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
        BatchMode=yes $USERNAME@$host "
      for i in \$(seq $ENABLED_CPUS 31); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
    "
  done
  fi
fi


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
        sudo mkdir -p collectl/data
        nohup sudo nice -n -1 /usr/bin/collectl -sCDmnt -i.05 -oTm -P -f collectl/data/coll > /dev/null 2>&1 &
      fi
    fi

    # Only activate rAdvisor if enabled
    if [[ \"$is_docker_instrumented\" -eq 1 ]]; then
      if [[ \"$ENABLE_RADVISOR\" -eq 1 ]]; then
        sudo mkdir -p $radvisor_stats
        sudo chmod +x ./artifacts/radvisor
        nohup sudo nice -n -1 ./artifacts/radvisor run docker -d $radvisor_stats -p $POLLING_INTERVAL -i ${COLLECTION_INTERVAL}ms > /dev/null 2>&1 &
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
    python $wise_home/microblog_bench/client/session.py --config $wise_home/experiments/indirect_response_time/conf/workload.yml --hostname $WEB_HOSTS --port 80 --prefix microblog > $wise_home/logs/session.log
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


# TODO tearing down
# TODO log collection


echo "[$(date +%s)] Cleanup:"
# <https://github.com/elba-kubernetes/moby/blob/277079e650c835624a303ed3de4f90d0f6db5814/daemon/stats.go#L51>
patched_moby_logs="/var/logs/docker/stats"


echo "[$(date +%s)] Cleanup:"
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
          # Stop event monitors.
          sudo rmmod spec_connect
          sudo rmmod spec_sendto
          sudo rmmod spec_recvfrom

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
        sudo mkdir -p logs
        if [[ \"$is_instrumented\" -eq 1 ]]; then
          if [[ \"$ENABLE_COLLECTL\" -eq 1 ]]; then
            sudo mkdir -p logs/collectl
            sudo mv $wise_home/collectl/data/coll-* logs/collectl
          fi

          sudo mkdir -p logs/milliscope
          cat /proc/spec_connect > logs/milliscope/spec_connect.csv
          cat /proc/spec_sendto > logs/milliscope/spec_sendto.csv
          cat /proc/spec_recvfrom > logs/milliscope/spec_recvfrom.csv
        fi

        if [[ \"$is_docker_instrumented\" -eq 1 ]]; then
          if [[ \"$ENABLE_RADVISOR\" -eq 1 ]]; then
            sudo mkdir -p logs/radvisor
            sudo mv $radvisor_stats/*.log logs/radvisor
          fi
          if [[ \"$USE_PATCHED_DOCKER\" -eq 1 ]]; then
            sudo mkdir -p logs/moby
            sudo mv $patched_moby_logs/*.log logs/moby
          fi
        fi
        
        sudo tar -C logs -czf log-${log_name}-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./
    " &
    wait $!
  done
done


echo "[$(date +%s)] Log data collection:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Collecting log data from host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $USERNAME@$host:log-*.tar.gz .
done
tar -czf results.tar.gz log-*.tar.gz conf/
