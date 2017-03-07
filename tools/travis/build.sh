#!/bin/bash
set -e
set -x

# Build script for Travis-CI.

SCRIPTDIR=$(cd $(dirname "$0") && pwd)
ROOTDIR="$SCRIPTDIR/../.."
WHISKDIR="$ROOTDIR/../openwhisk"

# Install OpenWhisk
cd $WHISKDIR/ansible

ANSIBLE_CMD="ansible-playbook -i environments/local  -e docker_image_prefix=testing"

$ANSIBLE_CMD setup.yml
$ANSIBLE_CMD prereq.yml
$ANSIBLE_CMD couchdb.yml
$ANSIBLE_CMD initdb.yml
$ANSIBLE_CMD apigateway.yml

cd $WHISKDIR

./gradlew distDocker -x :core:swift3Action:distDocker -x :core:pythonAction:distDocker -x :core:javaAction:distDocker -x :core:nodejsAction:distDocker -x :core:actionProxy:distDocker -x :sdk:docker:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker -PdockerImagePrefix=testing

cd $WHISKDIR/ansible

$ANSIBLE_CMD wipe.yml
$ANSIBLE_CMD openwhisk.yml

# Set Environment
export OPENWHISK_HOME=$WHISKDIR

# Test
cd $WHISKDIR
./gradlew tests:test -x :core:swift3Action:distDocker -x :core:pythonAction:distDocker -x :core:javaAction:distDocker -x :core:nodejsAction:distDocker  -x :core:actionProxy:distDocker -x :sdk:docker:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker --tests apigw.healthtests.* --tests whisk.core.apigw.actions.test.* --tests whisk.core.cli.test.ApiGwTests

