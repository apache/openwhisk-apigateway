#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -ex

# Build script for Travis-CI.
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
ROOTDIR="$SCRIPTDIR/../.."
HOMEDIR="$ROOTDIR/.."
WHISKDIR="$HOMEDIR/openwhisk"
UTILDIR="$HOMEDIR/incubator-openwhisk-utilities"
# Set Environment
export OPENWHISK_HOME=$WHISKDIR

# run scancode util. against project source using the ASF strict configuration
cd $UTILDIR
scancode/scanCode.py --config scancode/ASF-Release.cfg $ROOTDIR

# Install OpenWhisk
cd $OPENWHISK_HOME/ansible

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

$ANSIBLE_CMD wipe.yml
$ANSIBLE_CMD openwhisk.yml -e cli_installation_mode=remote -e controllerProtocolForSetup=http

#Use local
$ANSIBLE_CMD apigateway.yml -e apigateway_local_build=true

#Use dockerhub
#$ANSIBLE_CMD apigateway.yml

# Tests
cd $OPENWHISK_HOME
cat whisk.properties

WSK_TESTS_DEPS_EXCLUDE=""

TERM=dumb ./gradlew tests:test --tests apigw.healthtests.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep 60
TERM=dumb ./gradlew tests:test --tests whisk.core.apigw.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep 60
TERM=dumb ./gradlew tests:test --tests whisk.core.cli.test.ApiGwRestTests ${WSK_TESTS_DEPS_EXCLUDE}
