#!/bin/bash

# If using bare metal hosts, set with your CloudLab username.
# If using virtual machines (appendix A of the tutorial), set with "ubuntu".
readonly USERNAME="jazevedo"

# If using bare metal hosts, set with "physical".
# If using virtual machines (appendix A of the tutorial), set with "vm".
readonly HOSTS_TYPE="physical"

# If using profile MicroblogBareMetalD430, set with "d430".
# If using profile MicroblogBareMetalC8220, set with "c8220".
readonly HARDWARE_TYPE="c8220"

# Worker hosts to run benchmark execution on
#   Example (bare metal host): pc853.emulab.net
#   Example (virtual machine): 10.254.3.128
readonly WORKER_HOSTS="clnode058.clemson.cloudlab.us"

# Whether to use the patched docker version; either 0 or 1
readonly USE_PATCHED_DOCKER=1
# Whether to enable rAdvisor; either 0 or 1
readonly ENABLE_RADVISOR=1
# Whether to enable collectl; either 0 or 1
readonly ENABLE_COLLECTL=1

# Number of CPU cores to leave enabled
readonly ENABLED_CPUS="4"
# Number of containers to spawn as a part of the benchmark
readonly NUM_CONTAINERS="4"
# CPU quota per container to limit the effect of the CPU stressor
readonly CPU_PER_CONTAINER="0.5"
# Memory quota per container to limit the effect of the Memory stressor
readonly MEM_PER_CONTAINER="4g"
# Number of CPU stressor process forks to spawn (via `stress`)
readonly NUM_CPU_STRESSORS="2"
# Number of Memory stressor process forks to spawn (via `stress`)
readonly NUM_MEM_STRESSORS="2"
# Padding at the beginning of experiment
readonly PADDING="8s"
# Length of experiment
readonly STRESS_LENGTH="240s"
# Period between running the polling thread to find new collection targets
readonly POLLING_INTERVAL="6s"
# Period (ms) between collection ticks for radvisor/moby
readonly COLLECTION_INTERVAL="50"


containers_file=".containers"
bash -c "
    sudo docker run --cpus $CPU_PER_CONTAINER -it --memory $MEM_PER_CONTAINER jazevedo6/direct_collectl:v1.0 bash -c \"
        sleep $PADDING
        stress --cpu $NUM_CPU_STRESSORS --vm $NUM_MEM_STRESSORS --vm-bytes 128M --timeout $STRESS_LENGTH
        sleep $PADDING
    \"
"
