# If using bare metal hosts, set with your CloudLab username.
# If using virtual machines (appendix A of the tutorial), set with "ubuntu".
readonly USERNAME="<FILL IN>"

# If using bare metal hosts, set with "physical".
# If using virtual machines (appendix A of the tutorial), set with "vm".
readonly HOSTS_TYPE="<FILL IN>"

# If using profile MicroblogBareMetalD430, set with "d430".
# If using profile MicroblogBareMetalC8220, set with "c8220".
readonly HARDWARE_TYPE="<FILL IN>"

# Number of seconds to use when ramping up/down experiment (data ignored during)
readonly T_RAMP=<FILL_IN>
# Number of seconds to use as a buffer between phases where data is not collected
readonly T_BUFFER=<FILL_IN>
# Number of seconds to use to collect data
readonly T_COLLECTION=<FILL_IN>

# Number of CPU cores to leave enabled
readonly ENABLED_CPUS="4"
# Period for rAdvisor between running the polling thread to find new collection targets
readonly POLLING_INTERVAL="6s"
# Period between collection ticks for rAdvisor
readonly COLLECTION_INTERVAL="50ms"
# Number of sessions to run in the mock workload
readonly NUMBER_SESSIONS="160"
# Niceness to give to rAdvisor
readonly RADVISOR_NICENESS=-1
# Niceness to give to collectl
readonly COLLECTL_NICENESS=-1

# Whether to enable the load interference
readonly ENABLE_LOAD_INTERFERENCE=<FILL_IN>
# Number of stressor containers to spawn as a part of the benchmark during load interference
readonly NUM_STRESS_CONTAINERS="4"
# CPU quota per container to limit the effect of the CPU stressor
readonly CPU_PER_STRESS_CONTAINER="<FILL_IN>"
# Memory quota per container to limit the effect of the Memory stressor
readonly MEM_PER_STRESS_CONTAINER="4g"
# Number of CPU stressor process forks to spawn (via `stress`)
readonly NUM_CPU_STRESSORS="2"
# Number of Memory stressor process forks to spawn (via `stress`)
readonly NUM_MEM_STRESSORS="2"

# Whether to enable rAdvisor; either 0 or 1
readonly ENABLE_RADVISOR=1
# Whether to enable collectl; either 0 or 1
readonly ENABLE_COLLECTL=1

# Hostnames of each tier.
# Example (bare metal host): pc853.emulab.net
# Example (virtual machine): 10.254.3.128
readonly WEB_HOSTS="<FILL IN>"
readonly POSTGRESQL_HOST="<FILL IN>"
readonly WORKER_HOSTS="<FILL IN>"
# Microservice hostnames
readonly MICROBLOG_HOSTS="<FILL IN>"
readonly MICROBLOG_PORT=9090
readonly AUTH_HOSTS="<FILL IN>"
readonly AUTH_PORT=9091
readonly INBOX_HOSTS="<FILL IN>"
readonly INBOX_PORT=9092
readonly QUEUE_HOSTS="<FILL IN>"
readonly QUEUE_PORT=9093
readonly SUB_HOSTS="<FILL IN>"
readonly SUB_PORT=9094
# Client hostnames
readonly CLIENT_HOSTS="<FILL IN>"

# Path of the workload config yml file (relative to the experiment root)
readonly WORKLOAD_CONFIG="conf/workload.yml"
# Path of the session config yml file (relative to the experiment root)
readonly SESSION_CONFIG="conf/session.yml"

# Apache/mod_wsgi configuration.
readonly APACHE_PROCESSES=8
readonly APACHE_THREADSPERPROCESS=4

# Postgres configuration.
readonly POSTGRES_MAXCONNECTIONS=175

# Workers configuration.
readonly NUM_WORKERS=32

# Microservices configuration.
MICROBLOG_THREADPOOLSIZE=32
AUTH_THREADPOOLSIZE=32
INBOX_THREADPOOLSIZE=32
QUEUE_THREADPOOLSIZE=32
SUB_THREADPOOLSIZE=32

# Either 0 or 1.
readonly WISE_DEBUG=0
