# If using bare metal hosts, set with your CloudLab username.
# If using virtual machines (appendix A of the tutorial), set with "ubuntu".
readonly USERNAME="<FILL IN>"

# If using bare metal hosts, set with "physical".
# If using virtual machines (appendix A of the tutorial), set with "vm".
readonly HOSTS_TYPE="<FILL IN>"

# If using profile MicroblogBareMetalD430, set with "d430".
# If using profile MicroblogBareMetalC8220, set with "c8220".
readonly HARDWARE_TYPE="<FILL IN>"

# Hostnames of each tier.
# Example (bare metal host): pc853.emulab.net
# Example (virtual machine): 10.254.3.128
readonly CONTROL_PLANE_HOST="<FILL IN>"
readonly WEB_HOSTS="<FILL IN>"
readonly POSTGRESQL_HOST="<FILL IN>"
readonly WORKER_HOSTS="<FILL IN>"
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
readonly CLIENT_HOSTS="<FILL IN>"

# Apache/mod_wsgi configuration.
readonly APACHE_PROCESSES=8
readonly APACHE_THREADSPERPROCESS=4

# Postgres configuration.
readonly POSTGRES_MAXCONNECTIONS=100

# Workers configuration.
readonly NUM_WORKERS=32

# Microservices configuration.
AUTH_THREADPOOLSIZE=32
INBOX_THREADPOOLSIZE=32
QUEUE_THREADPOOLSIZE=32
SUB_THREADPOOLSIZE=32
MICROBLOG_THREADPOOLSIZE=32

# Either 0 or 1.
readonly WISE_DEBUG=0
