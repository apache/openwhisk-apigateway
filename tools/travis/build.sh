#!/bin/bash
set -e
set -x

# Build script for Travis-CI.
SCRIPTDIR=$(cd $(dirname "$0") && pwd)
ROOTDIR="$SCRIPTDIR/../.."
HOMEDIR="$ROOTDIR/.."
WHISKDIR="$ROOTDIR/../openwhisk"

# run the scancode util. against project source code starting at its root
cd $HOMEDIR
incubator-openwhisk-utilities/scancode/scanCode.py $ROOTDIR --config $ROOTDIR/tools/build/scanCode.cfg

# Install OpenWhisk
cd $WHISKDIR/ansible

ANSIBLE_CMD="ansible-playbook -i environments/local  -e docker_image_prefix=openwhisk"

$ANSIBLE_CMD setup.yml
$ANSIBLE_CMD prereq.yml
$ANSIBLE_CMD couchdb.yml
$ANSIBLE_CMD initdb.yml

# build docker image locally
pushd $ROOTDIR
pwd
docker build . -t "openwhisk/apigateway"
popd

#Use local
$ANSIBLE_CMD apigateway.yml -e apigateway_local_build=true

#Use dockerhub
#$ANSIBLE_CMD apigateway.yml

cd $WHISKDIR

TERM=dumb ./gradlew tools:cli:distDocker -PdockerImagePrefix=openwhisk

cd $WHISKDIR/ansible


$ANSIBLE_CMD wipe.yml
$ANSIBLE_CMD openwhisk.yml

# Set Environment
export OPENWHISK_HOME=$WHISKDIR

# Tests
cd $WHISKDIR
cat whisk.properties
WSK_TESTS_DEPS_EXCLUDE="-x :core:swift3Action:distDocker -x :core:pythonAction:distDocker -x :core:javaAction:distDocker -x :core:nodejsAction:distDocker -x :core:actionProxy:distDocker -x :sdk:docker:distDocker -x :core:python2Action:copyFiles -x :core:python2Action:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker"
TERM=dumb ./gradlew tests:test --tests apigw.healthtests.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep 60
TERM=dumb ./gradlew tests:test --tests whisk.core.apigw.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep 60
TERM=dumb ./gradlew tests:test --tests whisk.core.cli.test.ApiGwTests ${WSK_TESTS_DEPS_EXCLUDE}
