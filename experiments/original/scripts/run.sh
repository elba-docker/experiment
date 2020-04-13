#!/bin/bash

# Change to the parent directory.
cd $(dirname "$(dirname "$(readlink -fm "$0")")")


# Source configuration file.
source conf/config.sh


# Copy variables.
all_hosts="$CLIENT_HOSTS $WEB_HOSTS $POSTGRESQL_HOST $WORKER_HOSTS $MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"


echo "[$(date +%s)] Socket setup:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Limiting socket backlog in host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
      BatchMode=yes $USERNAME@$host "
    sudo sysctl -w net.core.somaxconn=$SOMAXCONN
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
wise_home="$fs_rootdir/WISETutorial"
sessions=()
n_sessions=0
for host in $all_hosts; do
  echo "  [$(date +%s)] Setting up common software in host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ~/.ssh/id_rsa $USERNAME@$host:.ssh
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
      BatchMode=yes $USERNAME@$host "
    # Synchronize apt.
    sudo apt-get update

    # Clone WISETutorial.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts
    rm -rf WISETutorial
    git clone git@github.com:coc-gatech-newelba/WISETutorial.git
    rm -rf $wise_home
    mv WISETutorial $fs_rootdir

    # Install Thrift
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y automake bison flex g++ git libboost-all-dev libevent-dev libssl-dev libtool make pkg-config
    tar -xzf $wise_home/experiment/artifacts/thrift-0.13.0.tar.gz -C .
    cd thrift-0.13.0
    ./bootstrap.sh
    ./configure --without-python
    make
    sudo make install

    # Install Collectl.
    cd $fs_rootdir
    tar -xzf $wise_home/experiment/artifacts/collectl-4.3.1.src.tar.gz -C .
    cd collectl-4.3.1
    sudo ./INSTALL

    # Set up Python 3 environment.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y virtualenv
    virtualenv -p `which python3` $wise_home/.env
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


echo "[$(date +%s)] Authentication microservice setup:"
sessions=()
n_sessions=0
for host in $AUTH_HOSTS; do
  echo "  [$(date +%s)] Setting up authentication microservice on host $host"

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-common
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-10

    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    pip install click
    pip install psycopg2-binary
    pip install thrift

    # Generate Thrift code.
    $wise_home/WISEServices/auth/scripts/gen_code.sh py

    # Setup database.
    $wise_home/WISEServices/auth/scripts/setup_database.sh $POSTGRESQL_HOST

    # Export configuration parameters.
    export WISE_DEBUG=$WISE_DEBUG

    $wise_home/WISEServices/auth/scripts/start_server.sh py 0.0.0.0 $AUTH_PORT $AUTH_THREADPOOLSIZE $POSTGRESQL_HOST
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Inbox microservice setup:"
sessions=()
n_sessions=0
for host in $INBOX_HOSTS; do
  echo "  [$(date +%s)] Setting up inbox microservice on host $host"

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-common
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-10

    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    pip install click
    pip install psycopg2-binary
    pip install thrift

    # Generate Thrift code.
    $wise_home/WISEServices/inbox/scripts/gen_code.sh py

    # Setup database.
    $wise_home/WISEServices/inbox/scripts/setup_database.sh $POSTGRESQL_HOST

    # Export configuration parameters.
    export WISE_DEBUG=$WISE_DEBUG

    $wise_home/WISEServices/inbox/scripts/start_server.sh py 0.0.0.0 $INBOX_PORT $INBOX_THREADPOOLSIZE $POSTGRESQL_HOST
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Queue microservice setup:"
sessions=()
n_sessions=0
for host in $QUEUE_HOSTS; do
  echo "  [$(date +%s)] Setting up queue microservice on host $host"

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-common
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-10

    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    pip install click
    pip install psycopg2-binary
    pip install thrift

    # Generate Thrift code.
    $wise_home/WISEServices/queue_/scripts/gen_code.sh py

    # Setup database.
    $wise_home/WISEServices/queue_/scripts/setup_database.sh $POSTGRESQL_HOST

    # Export configuration parameters.
    export WISE_DEBUG=$WISE_DEBUG

    $wise_home/WISEServices/queue_/scripts/start_server.sh py 0.0.0.0 $QUEUE_PORT $QUEUE_THREADPOOLSIZE $POSTGRESQL_HOST
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Subscription microservice setup:"
sessions=()
n_sessions=0
for host in $SUB_HOSTS; do
  echo "  [$(date +%s)] Setting up subscription microservice on host $host"

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-common
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-10

    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    pip install click
    pip install psycopg2-binary
    pip install thrift

    # Generate Thrift code.
    $wise_home/WISEServices/sub/scripts/gen_code.sh py

    # Setup database.
    $wise_home/WISEServices/sub/scripts/setup_database.sh $POSTGRESQL_HOST

    # Export configuration parameters.
    export WISE_DEBUG=$WISE_DEBUG

    $wise_home/WISEServices/sub/scripts/start_server.sh py 0.0.0.0 $SUB_PORT $SUB_THREADPOOLSIZE $POSTGRESQL_HOST
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Microblog microservice setup:"
sessions=()
n_sessions=0
for host in $MICROBLOG_HOSTS; do
  echo "  [$(date +%s)] Setting up microblog microservice on host $host"

  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-common
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client-10

    # Install Python dependencies.
    source $wise_home/.env/bin/activate
    pip install click
    pip install psycopg2-binary
    pip install thrift

    # Generate Thrift code.
    $wise_home/microblog_bench/services/microblog/scripts/gen_code.sh py

    # Setup database.
    $wise_home/microblog_bench/services/microblog/scripts/setup_database.sh $POSTGRESQL_HOST

    # Export configuration parameters.
    export WISE_DEBUG=$WISE_DEBUG

    $wise_home/microblog_bench/services/microblog/scripts/start_server.sh py 0.0.0.0 $MICROBLOG_PORT $MICROBLOG_THREADPOOLSIZE $POSTGRESQL_HOST
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


echo "[$(date +%s)] Client setup:"
sessions=()
n_sessions=0
for host in $CLIENT_HOSTS; do
  echo "  [$(date +%s)] Setting up client on host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no conf/workload.yml $USERNAME@$host:$wise_home/experiment/conf
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no conf/session.yml $USERNAME@$host:$wise_home/experiment/conf
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
    sed -i \"s/{{WISEHOME}}/\$WISEHOME/g\" $wise_home/experiment/conf/workload.yml
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
        for i in \$(seq $CPUCORES 39); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
      "
    done
  fi
  if [[ $HARDWARE_TYPE = "d430" ]]; then
    for host in $all_hosts; do
      echo "  [$(date +%s)] Disabling cores in host $host"
      ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
          BatchMode=yes $USERNAME@$host "
        for i in \$(seq $CPUCORES 31); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
      "
    done
  fi
fi


echo "[$(date +%s)] System instrumentation:"
sessions=()
n_sessions=0
for host in $all_hosts; do
  echo "  [$(date +%s)] Instrumenting host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
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

    # Activate Collectl.
    cd $wise_home
    mkdir -p collectl/data
    nohup sudo nice -n -1 /usr/bin/collectl -sCDmnt -i.05 -oTm -P -f collectl/data/coll > /dev/null 2>&1 &
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

    # [TODO] Load balance.
    mkdir -p $wise_home/logs
    python $wise_home/microblog_bench/client/session.py --config $wise_home/experiment/conf/workload.yml --hostname $WEB_HOSTS --port 80 --prefix microblog > $wise_home/logs/session.log
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Client tear down:"
for host in $CLIENT_HOSTS; do
  echo "  [$(date +%s)] Tearing down client on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-client-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Web tear down:"
for host in $WEB_HOSTS; do
  echo "  [$(date +%s)] Tearing down web server on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/microblog_bench/web/scripts/stop_server.sh apache

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-web-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Worker tear down:"
for host in $WORKER_HOSTS; do
  echo "  [$(date +%s)] Tearing down workers on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/microblog_bench/worker/scripts/stop_workers.sh

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-worker-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Microblog microservice tear down:"
for host in $MICROBLOG_HOSTS; do
  echo "  [$(date +%s)] Tearing down microblog microservice on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/microblog_bench/services/microblog/scripts/stop_server.sh

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-microblog-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Subscription microservice tear down:"
for host in $SUB_HOSTS; do
  echo "  [$(date +%s)] Tearing down subscription microservice on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/WISEServices/sub/scripts/stop_server.sh

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-sub-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Queue microservice tear down:"
for host in $QUEUE_HOSTS; do
  echo "  [$(date +%s)] Tearing down queue microservice on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/WISEServices/queue_/scripts/stop_server.sh

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-queue-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Inbox microservice tear down:"
for host in $INBOX_HOSTS; do
  echo "  [$(date +%s)] Tearing down inbox microservice on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/WISEServices/inbox/scripts/stop_server.sh

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-inbox-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Authentication microservice tear down:"
for host in $AUTH_HOSTS; do
  echo "  [$(date +%s)] Tearing down authentication microservice on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/WISEServices/auth/scripts/stop_server.sh

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-auth-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Database tear down:"
for host in $POSTGRESQL_HOST; do
  echo "  [$(date +%s)] Tearing down database server on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop server.
    $wise_home/microblog_bench/postgres/scripts/stop_postgres.sh

    # Stop resource monitors.
    sudo pkill collectl
    sleep 8

    # Collect log data.
    mkdir logs
    mv $wise_home/collectl/data/coll-* logs/
    gzip -d logs/coll-*
    cat /proc/spec_connect > logs/spec_connect.csv
    cat /proc/spec_sendto > logs/spec_sendto.csv
    cat /proc/spec_recvfrom > logs/spec_recvfrom.csv
    tar -C logs -czf log-db-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./

    # Stop event monitors.
    sudo rmmod spec_connect
    sudo rmmod spec_sendto
    sudo rmmod spec_recvfrom
  "
done


echo "[$(date +%s)] Log data collection:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Collecting log data from host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $USERNAME@$host:log-*.tar.gz .
done
tar -czf results.tar.gz log-*.tar.gz conf/