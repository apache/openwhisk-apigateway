#!/bin/bash

SCRIPTDIR=$(cd $(dirname "$0") && pwd)
HOMEDIR="$SCRIPTDIR/../../../"

sudo gpasswd -a travis docker
sudo -E bash -c 'echo '\''DOCKER_OPTS="-H tcp://0.0.0.0:4243 -H unix:///var/run/docker.sock --storage-driver=overlay --userns-remap=default"'\'' > /etc/default/docker'

# Docker
sudo apt-get -y update -qq
sudo apt-get -o Dpkg::Options::="--force-confold" --force-yes -y install docker-engine=1.12.0-0~trusty
sudo service docker restart
echo "Docker Version:"
docker version
echo "Docker Info:"
docker info

# Python
pip install --user jsonschema
pip install --user couchdb

# Ansible
pip install --user ansible==2.3.0.0

# jshint support
sudo apt-get -y install nodejs npm
sudo npm install -g jshint

# clone OpenWhisk main repo.
cd $HOMEDIR
git clone --depth=1 https://github.com/apache/incubator-openwhisk.git openwhisk

# clone the openwhisk utilities repo.
git clone https://github.com/apache/incubator-openwhisk-utilities.git
