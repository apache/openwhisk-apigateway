#!/bin/sh
set -e

apk add --update git

cd apigateway/api-gateway-config/tests
./install-deps.sh
./run-tests.sh