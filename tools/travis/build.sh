#!/bin/bash
set-e
set-x

#Build script for Travis-CI.

SCRIPTDIR=$(cd$(dirname "$0") && pwd)
ROOTDIR="$SCRIPTDIR/../.."
WHISKDIR="$ROOTDIR/../openwhisk"

#Install OpenWhisk
cd$WHISKDIR/ansible

ANSIBLE_CMD="ansible-playbook-i environments/local  -e docker_image_prefix=openwhisk"

$ANSIBLE_CMDsetup.yml
$ANSIBLE_CMDprereq.yml
$ANSIBLE_CMDcouchdb.yml
$ANSIBLE_CMDinitdb.yml

#builddocker image locally
pushd$ROOTDIR
pwd
dockerbuild . -t "openwhisk/apigateway"
popd

#Uselocal
$ANSIBLE_CMDapigateway.yml -e apigateway_local_build=true

#Usedockerhub
#$ANSIBLE_CMDapigateway.yml

cd$WHISKDIR

TERM=dumb./gradlew tools:cli:distDocker -PdockerImagePrefix=openwhisk

cd$WHISKDIR/ansible


$ANSIBLE_CMDwipe.yml
$ANSIBLE_CMDopenwhisk.yml

#Set Environment
exportOPENWHISK_HOME=$WHISKDIR

#Tests
cd$WHISKDIR
catwhisk.properties
WSK_TESTS_DEPS_EXCLUDE="-x:core:swift3Action:distDocker -x :core:pythonAction:distDocker -x :core:javaAction:distDocker -x :core:nodejsAction:distDocker -x :core:actionProxy:distDocker -x :sdk:docker:distDocker -x :core:python2Action:copyFiles -x :core:python2Action:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker"
TERM=dumb./gradlew tests:test --tests apigw.healthtests.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep60
TERM=dumb./gradlew tests:test --tests whisk.core.apigw.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep60
TERM=dumb./gradlew tests:test --tests whisk.core.cli.test.ApiGwTests ${WSK_TESTS_DEPS_EXCLUDE}
sleep60


#Test again with cassandra
cd$SCRIPTDIR
cpdeploy.yml $WHISKDIR/ansible/roles/apigateway/tasks

#builddocker image locally
pushd$ROOTDIR
pwd
dockerbuild . -t "openwhisk/apigateway"
popd

# cd../../../openwhisk/ansible

#Uselocal
$ANSIBLE_CMDapigateway.yml -e apigateway_local_build=true

#Usedockerhub
#$ANSIBLE_CMDapigateway.yml

cd$WHISKDIR

TERM=dumb./gradlew tools:cli:distDocker -PdockerImagePrefix=openwhisk

cd$WHISKDIR/ansible


$ANSIBLE_CMDwipe.yml
$ANSIBLE_CMDopenwhisk.yml

#Set Environment
exportOPENWHISK_HOME=$WHISKDIR

#Tests
cd$WHISKDIR
catwhisk.properties
WSK_TESTS_DEPS_EXCLUDE="-x:core:swift3Action:distDocker -x :core:pythonAction:distDocker -x :core:javaAction:distDocker -x :core:nodejsAction:distDocker -x :core:actionProxy:distDocker -x :sdk:docker:distDocker -x :core:python2Action:copyFiles -x :core:python2Action:distDocker -x :tests:dat:blackbox:badaction:distDocker -x :tests:dat:blackbox:badproxy:distDocker"
TERM=dumb./gradlew tests:test --tests apigw.healthtests.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep60
TERM=dumb./gradlew tests:test --tests whisk.core.apigw.* ${WSK_TESTS_DEPS_EXCLUDE}
sleep60
TERM=dumb./gradlew tests:test --tests whisk.core.cli.test.ApiGwTests ${WSK_TESTS_DEPS_EXCLUDE}
sleep60



