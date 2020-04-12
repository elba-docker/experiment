FROM ubuntu:bionic
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y wget build-essential
WORKDIR "/"
RUN wget "https://github.com/elba-kubernetes/nbench/archive/v2-linux.tar.gz" && tar -xvf v2-linux.tar.gz
WORKDIR "/nbench-2-linux"
RUN make
CMD ["/bin/bash"]
