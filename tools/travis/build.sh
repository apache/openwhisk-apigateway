#!/bin/bash
set -e
set -x

# Build script for Travis-CI.

SCRIPTDIR=$(cd $(dirname "$0") && pwd)
ROOTDIR="$SCRIPTDIR/../.."
WHISKDIR="$ROOTDIR/../openwhisk"

# Install OpenWhisk
cd $WHISKDIR/ansible

ANSIBLE_CMD="ansible-playbook -i environments/local  -e docker_image_prefix=openwhisk"

$ANSIBLE_CMD setup.yml
$ANSIBLE_CMD prereq.yml
$ANSIBLE_CMD couchdb.yml
$ANSIBLE_CMD initdb.yml

#build docker image locally 
pushd $ROOTDIR
pwd
docker build . -t "openwhisk/apigateway" 
popd

#Use local
$ANSIBLE_CMD apigateway.yml -e apigateway_local_build=true

#Use dockerhub
#$ANSIBLE_CMD apigateway.yml

cd $WHISKDIR

./gradlew tools:cli:distDocker -PdockerImagePrefix=openwhisk

cd $WHISKDIR/ansible


$ANSIBLE_CMD wipe.yml
$ANSIBLE_CMD openwhisk.yml

# Set Environment
export OPENWHISK_HOME=$WHISKDIR

# Test
cd $WHISKDIR
cat whisk.properties
./gradlew tests:test -x :core:swift3Action:distDocker -x :core:pythonAction:distDocker -x :core:javaAction:distDocker -x :core:nodejsAction:distDocker  -x :core:actionProxy:distDocker -x :sdk:docker:distDocker -x :core:python2Action:copyFiles -x :core:python2Action:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker --tests apigw.healthtests.* --tests whisk.core.apigw.* --tests whisk.core.cli.test.ApiGwTests
