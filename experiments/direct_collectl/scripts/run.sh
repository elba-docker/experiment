#!/bin/bash

# Direct overhead measurement via running collectl side-by-side with radvisor
# Repeats the experiment according to the number of hosts given in the $WORKER_HOSTS variable
# from ./conf/config.sh

# Change to the parent directory.
cd $(dirname "$(dirname "$(readlink -fm "$0")")")
echo "[$(date +%s)] CD: $(pwd)"

# Source configuration file.
source conf/config.sh

# Copy variables.
all_hosts="$WORKER_HOSTS"


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
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ~/.ssh/id_rsa $USERNAME@$host:.ssh
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o \
      BatchMode=yes $USERNAME@$host "
    # Synchronize apt.
    sudo apt-get update

    # Install Docker.
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn apt-key add -
    sudo add-apt-repository \\
      \"deb [arch=amd64] https://download.docker.com/linux/ubuntu \\
      \$(lsb_release -cs) \\
      stable\"
    ## Install Docker CE.
    sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\
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

    # Clone wise-kubernetes.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
    sudo rm -rf $wise_home
    sudo mkdir $wise_home
    sudo git clone https://github.com/elba-kubernetes/experiment.git $wise_home

    # Install Collectl.
    cd $fs_rootdir
    sudo tar -xzf $wise_home/artifacts/collectl-4.3.1.src.tar.gz -C .
    cd collectl-4.3.1
    sudo ./INSTALL
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
for host in $all_hosts; do
  echo "  [$(date +%s)] Instrumenting host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Activate Collectl.
    cd $wise_home
    sudo mkdir -p collectl/data
    nohup sudo nice -n -1 /usr/bin/collectl -sCDmnt -i.05 -oTm -P -f collectl/data/coll > /dev/null 2>&1 &

    # Activate rAdvisor.
    sudo mkdir -p radvisor/data
    sudo chmod +x ./artifacts/radvisor
    nohup sudo nice -n -1 ./artifacts/radvisor run docker -d radvisor/out > /dev/null 2>&1 &
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


echo "[$(date +%s)] Benchmark execution:"
sessions=()
n_sessions=0
for host in $all_hosts; do
  echo "  [$(date +%s)] Generating stressors on $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Run docker containers
    for i in {1..$NUM_CONTAINERS}
    do
        sudo docker run --cpus $CPU_PER_CONTAINER -d --memory $MEM_PER_CONTAINER ubuntu bash -c \" \\
            apt-get update; \\
            apt-get install stress; \\
            stress --cpu $NUM_CPU_STRESSORS --vm $NUM_MEM_STRESSORS --vm-bytes 128M --timeout $STRESS_LENGTH
        \"
    done
  " &
  sessions[$n_sessions]=$!
  let n_sessions=n_sessions+1
done
for session in ${sessions[*]}; do
  wait $session
done


# Wait for the benchmarks to complete
sleep $STRESS_LENGTH
sleep 20s


echo "[$(date +%s)] Cleanup:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Tearing down worker on host $host"
  ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      -o BatchMode=yes $USERNAME@$host "
    # Stop and remove all docker containers
    sudo docker stop \$(sudo docker ps -aq)
    sudo docker rm \$(sudo docker ps -aq)
    sleep 4s
    
    # Stop resource monitors.
    sudo pkill collectl
    sudo pkill radvisor
    sleep 4s

    # Collect log data.
    sudo mkdir -p logs
    sudo mv $wise_home/collectl/data/coll-* logs/
    sudo mv $wise_home/radvisor/stats/*.log logs/
    sudo tar -C logs -czf log-worker-\$(echo \$(hostname) | awk -F'[-.]' '{print \$1\$2}').tar.gz ./
  "
done


echo "[$(date +%s)] Log data collection:"
for host in $all_hosts; do
  echo "  [$(date +%s)] Collecting log data from host $host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $USERNAME@$host:log-*.tar.gz .
done
tar -czf results.tar.gz log-*.tar.gz conf/
