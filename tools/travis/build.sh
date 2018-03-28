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

set -e
set -x

# Build script for Travis-CI.
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
ROOTDIR=$(cd "$SCRIPTDIR/../.." && pwd)
WHISKDIR=$(cd "$ROOTDIR/../openwhisk" && pwd)
UTILDIR=$(cd "$ROOTDIR/../incubator-openwhisk-utilities" && pwd)

# run the scancode util. against project source code starting at its root
cd "$UTILDIR"
scancode/scanCode.py --config scancode/ASF-Release.cfg "$ROOTDIR"

# Install OpenWhisk
cd "$WHISKDIR/ansible"

ANSIBLE_CMD="ansible-playbook -i environments/local  -e docker_image_prefix=openwhisk"

$ANSIBLE_CMD setup.yml
$ANSIBLE_CMD prereq.yml
$ANSIBLE_CMD couchdb.yml
$ANSIBLE_CMD initdb.yml

# build docker image
pushd "$ROOTDIR"
pwd
./gradlew --console=plain :core:apigateway:dockerBuildImage
popd

#Use local
$ANSIBLE_CMD apigateway.yml -e apigateway_local_build=true

#Use dockerhub
#$ANSIBLE_CMD apigateway.yml

$ANSIBLE_CMD wipe.yml
$ANSIBLE_CMD openwhisk.yml -e cli_installation_mode=remote -e controllerProtocolForSetup=http

# Set Environment
export OPENWHISK_HOME=$WHISKDIR

# Tests
cd "$WHISKDIR"
cat whisk.properties

WSK_TESTS_DEPS_EXCLUDE=( -x :actionRuntimes:pythonAction:distDocker -x :actionRuntimes:javaAction:distDocker -x :actionRuntimes:nodejs6Action:distDocker -x :actionRuntimes:nodejs8Action:distDocker -x :actionRuntimes:actionProxy:distDocker -x :sdk:docker:distDocker -x :actionRuntimes:python2Action:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker )

./gradlew --console=plain :tests:test --tests "apigw.healthtests.*" "${WSK_TESTS_DEPS_EXCLUDE[@]}"
echo 'Sleeping 60... never fear'; sleep 60
./gradlew --console=plain :tests:test --tests "whisk.core.apigw.*" "${WSK_TESTS_DEPS_EXCLUDE[@]}"
echo 'Sleeping 60... never fear'; sleep 60
./gradlew --console=plain :tests:test --tests "whisk.core.cli.test.ApiGwRestTests" "${WSK_TESTS_DEPS_EXCLUDE[@]}"
