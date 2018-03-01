#!/bin/bash
set -e
set -x


# Build script for Travis-CI.
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
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


$ANSIBLE_CMD wipe.yml
$ANSIBLE_CMD openwhisk.yml -e cli_installation_mode=remote

# Set Environment
export OPENWHISK_HOME=$WHISKDIR

# Tests
cd $WHISKDIR
cat whisk.properties

WSK_TESTS_DEPS_EXCLUDE="-x :actionRuntimes:pythonAction:distDocker -x :actionRuntimes:javaAction:distDocker -x :actionRuntimes:nodejs6Action:distDocker -x :actionRuntimes:nodejs8Action:distDocker -x :actionRuntimes:actionProxy:distDocker -x :sdk:docker:distDocker -x :actionRuntimes:python2Action:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker"

TERM=dumb ./gradlew tests:test --tests apigw.healthtests.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep 60
TERM=dumb ./gradlew tests:test --tests whisk.core.apigw.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep 60
TERM=dumb ./gradlew tests:test --tests whisk.core.cli.test.ApiGwRestTests ${WSK_TESTS_DEPS_EXCLUDE}
