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

#
#  TODO:  Use 'latest'; override with "latest-$(uname -m)" for multiarch
#
#DOCKER_TAG ?= snapshot-`date +'%Y%m%d-%H%M'`

OPENWHISK_TARGET_REGISTRY ?= docker.io
OPENWHISK_TARGET_PREFIX ?= openwhisk
OPENWHISK_TARGET_TAG ?= latest

RUNTIME := ${OPENWHISK_TARGET_REGISTRY}/${OPENWHISK_TARGET_PREFIX}/apigateway:${OPENWHISK_TARGET_TAG}
PROFILING := ${OPENWHISK_TARGET_REGISTRY}/${OPENWHISK_TARGET_PREFIX}/apigateway-profiling:${OPENWHISK_TARGET_TAG}

docker:
	docker build -t ${RUNTIME} .

.PHONY: docker-ssh
docker-ssh:
	docker run -ti --entrypoint='bash' ${RUNTIME}

.PHONY: test-build
test-build:
	cd tests; ./install-deps.sh

.PHONY: profile-build
profile-build:
	./build_profiling.sh
	docker build -t ${PROFILING} -f Dockerfile.profiling .

.PHONY: profile-run
profile-run: profile-build
	docker run --rm --name="apigateway" --privileged -p 80:80 -p ${PUBLIC_MANAGEDURL_PORT}:8080 -p 9000:9000 \
		-e PUBLIC_MANAGEDURL_HOST=${PUBLIC_MANAGEDURL_HOST} -e PUBLIC_MANAGEDURL_PORT=${PUBLIC_MANAGEDURL_PORT} \
		-e REDIS_HOST=${REDIS_HOST} -e REDIS_PORT=${REDIS_PORT} -e REDIS_PASS=${REDIS_PASS} \
		-e TOKEN_GOOGLE_URL=https://www.googleapis.com/oauth2/v3/tokeninfo \
	 	-e TOKEN_FACEBOOK_URL=https://graph.facebook.com/debug_token \
		-e TOKEN_GITHUB_URL=https://api.github.com/user \
		-e DEBUG=true \
		-e CACHING_ENABLED=true \
		-e CACHE_SIZE=2048 \
		-e CACHE_TTL=180 \
		-e OPTIMIZE=1 \
		-d ${PROFILING}

.PHONY: test-run
test-run:
	cd tests; ./run-tests.sh

.PHONY: docker-run
docker-run:
	docker run --rm --name="apigateway" -p 80:80 -p ${PUBLIC_MANAGEDURL_PORT}:8080 -p 9000:9000 \
		-e PUBLIC_MANAGEDURL_HOST=${PUBLIC_MANAGEDURL_HOST} -e PUBLIC_MANAGEDURL_PORT=${PUBLIC_MANAGEDURL_PORT} \
		-e REDIS_HOST=${REDIS_HOST} -e REDIS_PORT=${REDIS_PORT} -e REDIS_PASS=${REDIS_PASS} \
		-e DECRYPT_REDIS_PASS=${DECRYPT_REDIS_PASS} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e ENCRYPTION_IV=${ENCRYPTION_IV} \
		-e TOKEN_GOOGLE_URL=https://www.googleapis.com/oauth2/v3/tokeninfo \
	 	-e TOKEN_FACEBOOK_URL=https://graph.facebook.com/debug_token \
		-e TOKEN_GITHUB_URL=https://api.github.com/user \
		-e APPID_PKURL=https://appid-oauth.ng.bluemix.net/oauth/v3/ \
		-e LD_LIBRARY_PATH=/usr/local/lib \
		${TARGET}

.PHONY: docker-debug
docker-debug:
	#Volumes directories must be under your Users directory
	mkdir -p ${HOME}/tmp/apiplatform/apigateway
	rm -rf ${HOME}/tmp/apiplatform/apigateway
	cp -r `pwd` ${HOME}/tmp/apiplatform/apigateway/
	docker run --name="apigateway" \
			-p 80:80 -p 5000:5000 \
			-e "LOG_LEVEL=info" -e "DEBUG=true" \
			-v ${HOME}/tmp/apiplatform/apigateway/:/etc/api-gateway \
			${TARGET}

.PHONY: docker-reload
docker-reload:
	cp -r `pwd` ${HOME}/tmp/apiplatform/apigateway/
	docker exec apigateway api-gateway -t -p /usr/local/api-gateway/ -c /etc/api-gateway/api-gateway.conf
	docker exec apigateway api-gateway -s reload

.PHONY: docker-attach
docker-attach:
	docker exec -i -t apigateway bash

.PHONY: docker-stop
docker-stop:
	docker stop apigateway
	docker rm apigateway
