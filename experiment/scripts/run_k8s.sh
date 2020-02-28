#!/bin/bash

# Change to the parent directory.
cd $(dirname "$(dirname "$(readlink -fm "$0")")")


# Source configuration file.
source conf/config.sh


# Copy variables.
all_node_hosts="$CLIENT_HOSTS $WEB_HOSTS $POSTGRESQL_HOST $WORKER_HOSTS $MICROBLOG_HOSTS $AUTH_HOSTS $INBOX_HOSTS $QUEUE_HOSTS $SUB_HOSTS"
all_hosts="$CONTROL_PLANE_HOST $all_node_hosts"


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
for host in $all_hosts; do
  echo "  [$(date +%s)] Setting up common software in host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ~/.ssh/id_rsa $USERNAME@$host:.ssh
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
      BatchMode=yes $USERNAME@$host "
    # Synchronize apt.
    sudo apt-get update

    # Disable swap for kubelet/kubeadm to work.
    sudo swapoff -a

    # Install Docker.
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) \
      stable"
    ## Install Docker CE.
    sudo apt-get update && sudo apt-get install -y \
      containerd.io=1.2.10-3 \
      docker-ce=5:19.03.4~3-0~ubuntu-$(lsb_release -cs) \
      docker-ce-cli=5:19.03.4~3-0~ubuntu-$(lsb_release -cs)
    # Setup daemon.
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
    sudo mkdir -p /etc/systemd/system/docker.service.d
    # Restart docker.
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    # Install kubeadm
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
    deb https://apt.kubernetes.io/ kubernetes-xenial main
    EOF
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

    # Install Collectl.
    cd $fs_rootdir
    tar -xzf $wise_home/experiment/artifacts/collectl-4.3.1.src.tar.gz -C .
    cd collectl-4.3.1
    sudo ./INSTALL
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Setting up control plane server on host $CONTROL_PLANE_HOST"
ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    -o BatchMode=yes $USERNAME@$CONTROL_PLANE_HOST "
  # Synchronize apt.
  sudo apt-get update

  # Clone wise-kubernetes.
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
  ssh-keyscan -H github.com >> ~/.ssh/known_hosts
  rm -rf wise-kubernetes
  git clone git@github.com:jazevedo620/wise-kubernetes.git
  rm -rf $wise_home
  mv wise-kubernetes $fs_rootdir

  # Required for flannel to operate.
  sudo sysctl net.bridge.bridge-nf-call-iptables=1

  # Initialize the control plane
  sudo kubeadm config images pull
  sudo kubeadm init --pod-network-cidr=10.244.0.0/16

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
  export KUBECONFIG=$HOME/.kube/config

  sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/2140ac876ef134e0ed5af15c65e414cf26827915/Documentation/kube-flannel.yml
  sudo kubeadm token create --print-join-command 2>/dev/null > $fs_rootdir/wise-kubernetes/join_command.txt
" &
session=$!
wait $session
# Retreive join command from remote node
scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $USERNAME@$CONTROL_PLANE_HOST:$fs_rootdir/wise-kubernetes/join_command.txt join_command.txt
cat join_command.txt > $join_command


echo "[$(date +%s)] Joining all nodes to cluster"
sessions=()
n_sessions=0
for host in $all_hosts; do
  echo "  [$(date +%s)] Joining cluster for host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ~/.ssh/id_rsa $USERNAME@$host:.ssh
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
      BatchMode=yes $USERNAME@$host "
    sudo $join_command
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
    # Clone wise-kubernetes.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts
    rm -rf wise-kubernetes
    git clone git@github.com:jazevedo620/wise-kubernetes.git
    rm -rf $wise_home
    mv wise-kubernetes $fs_rootdir

    # Set up Python 3 environment.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y virtualenv
    virtualenv -p `which python3` $wise_home/.env

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
      for i in \$(seq 4 39); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
    "
  done
  fi
  if [[ $HARDWARE_TYPE = "d430" ]]; then
  for host in $all_hosts; do
    echo "  [$(date +%s)] Disabling cores in host $host"
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
        BatchMode=yes $USERNAME@$host "
      for i in \$(seq 4 31); do echo 0 | sudo tee /sys/devices/system/cpu/cpu\$i/online; done
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


# TODO write k8s deployment config
# TODO render with environment variables like workload.yml
echo "[$(date +%s)] Applying kubernetes deployment config to control plane host $CONTROL_PLANE_HOST"
ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    -o BatchMode=yes $USERNAME@$CONTROL_PLANE_HOST "
  sudo kubectl apply -f $fs_rootdir/wise-kubernetes/conf/deployment.yml
" &
session=$!
wait $session


sleep 120


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


# TODO node teardown, log collection/archiving


echo "[$(date +%s)] Log data collection:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Collecting log data from host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $USERNAME@$host:log-*.tar.gz .
done
tar -czf results.tar.gz log-*.tar.gz conf/
