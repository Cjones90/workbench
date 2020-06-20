#!/bin/sh
set -e

# DEFAULT_DOCKER_VER=18.02.0
# DOCKER_VER=5:19.03.4~3-0~ubuntu-xenial
#
# if [ -z $DOCKER_VER ] || [ $DOCKER_VER = "" ] || [ $DOCKER_VER = %%%REPLACE_ME%%% ]; then
#     DOCKER_VER=$DEFAULT_DOCKER_VER
# fi

# apt-get remove docker docker-engine docker.io containerd runc

apt-get update

apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common -y

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# Add 'edge' for even new releases

apt-get update

# Going to use for debugging why a particular version not available/installed
apt-cache madison docker-ce


# Trying to ramp up our vm provisioning/releases and keep up with gitlab and docker version releases
# Any point they are a major version behind we should be intentionally upgrading
# Otherwise it is VERY easy to fall behind and need to skip multiple releases which is no bueno
apt-get install docker-ce docker-ce-cli containerd.io -y


# Enable docker on boot
sudo systemctl enable docker

#systemctl daemon reload
#sleep 10
#systemctl restart docker
#sleep 20