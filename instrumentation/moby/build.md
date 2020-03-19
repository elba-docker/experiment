# Building modified moby

On a system with `git` and [`docker`](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-using-the-repository) installed,

```bash
mkdir ~/dev
cd ~/dev
git clone git@github.com:elba-kubernetes/moby.git
git clone git@github.com:elba-kubernetes/docker-ce.git
cd docker-ce/components/packaging/deb
export VERSION=19.03.8-elba
sudo make ENGINE_DIR=~/dev/moby CLI_DIR=~/dev/docker-ce/components/cli VERSION=19.03.8-elba ubuntu-bionic
```

The built artifacts should be in `~/dev/docker-ce/components/packaging/deb/debbuild/ubuntu-bionic/`.

> **Note**: only tested on a Ubuntu 18.04 host
