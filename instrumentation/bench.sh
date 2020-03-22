# Benchmark used to generate system monitor logs that is designed to stress
# a variety of system resources, such as network, cpu, memory, and I/O
# Note: Outputs nano timestamps each command, preceded by `__N\n` where N
#       is an incrementing hex digit
docker run -it ubuntu bash -c " \
    echo __1; date +%s%N; \
    sleep 2s; \
    echo __2; date +%s%N; \
    apt-get update; \
    echo __3; date +%s%N; \
    sleep 2s; \
    echo __4; date +%s%N; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y tree stress wget; \
    echo __5; date +%s%N; \
    sleep 2s; \
    echo __6; date +%s%N; \
    tree; \
    echo __7; date +%s%N; \
    sleep 2s; \
    echo __8; date +%s%N; \
    stress --cpu 8 --io 4 --vm 4 --vm-bytes 1024M --timeout 10s; \
    echo __9; date +%s%N; \
    sleep 2s; \
    echo __A; date +%s%N; \
    wget \"http://ipv4.download.thinkbroadband.com/10MB.zip\"; \
    echo __B; date +%s%N; \
    sleep 2s \
    echo __C; date +%s%N; \
" > bench_run_$(date -I)_$(date +"%T.%3N").out
