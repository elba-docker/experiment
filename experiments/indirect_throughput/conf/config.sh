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
readonly WORKER_HOSTS="clnode096.clemson.cloudlab.us"

# Whether to use the patched docker version; either 0 or 1
readonly USE_PATCHED_DOCKER=<FILL IN>
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
# Minimum number of CPU ticks (1/100ths of a second) to elapse
# for each stress test iteration (or it scales up the difficulty)
readonly MIN_TICKS_PER_ITER="240"
# Padding at the beginning of experiment
readonly PADDING="8s"
# Length of experiment
readonly STRESS_LENGTH="900s"
# Period between running the polling thread to find new collection targets
readonly POLLING_INTERVAL="6s"
# Period (ms) between collection ticks for radvisor/moby
readonly COLLECTION_INTERVAL="50"
