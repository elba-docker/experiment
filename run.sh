#!/bin/bash

# Direct overhead measurement via running collectl side-by-side with radvisor
# Repeats the experiment according to the number of hosts given in the $WORKER_HOSTS variable
# from ./conf/config.sh

# Change to the parent directory.
echo $(pwd)
cd $(dirname "$(dirname "$(readlink -fm "$0")")")
echo $(pwd)
