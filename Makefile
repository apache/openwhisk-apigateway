DOCKER_TAG ?= snapshot-`date +'%Y%m%d-%H%M'`
DOCKER_REGISTRY ?= ''

docker:
	docker build -t openwhisk/apigateway .

.PHONY: docker-ssh
docker-ssh:
	docker run -ti --entrypoint='bash' openwhisk/apigateway:latest

.PHONY: test-build
test-build:
	cd tests; ./install-deps.sh

.PHONY: profile-build
profile-build:
	./build_profiling.sh
	docker build -t openwhisk/apigateway-profiling -f Dockerfile.profiling .

.PHONY: profile-run
profile-run: profile-build 
	docker run --rm --name="apigateway" --privileged -p 80:80 -p ${PUBLIC_MANAGEDURL_PORT}:8080 -p 9000:9000 \
		-e PUBLIC_MANAGEDURL_HOST=${PUBLIC_MANAGEDURL_HOST} -e PUBLIC_MANAGEDURL_PORT=${PUBLIC_MANAGEDURL_PORT} \
		-e REDIS_HOST=${REDIS_HOST} -e REDIS_PORT=${REDIS_PORT} -e REDIS_PASS=${REDIS_PASS} \
		-e TOKEN_GOOGLE_URL=https://www.googleapis.com/oauth2/v3/tokeninfo \
	 	-e TOKEN_FACEBOOK_URL=https://graph.facebook.com/debug_token \
		-e TOKEN_GITHUB_URL=https://api.github.com/user \
		-e DEBUG=true \
		-d openwhisk/apigateway-profiling:latest

.PHONY: test-run
test-run:
	cd tests; ./run-tests.sh

.PHONY: docker-run
docker-run:
	docker run --rm --name="apigateway" -p 80:80 -p ${PUBLIC_MANAGEDURL_PORT}:8080 -p 9000:9000 \
		-e PUBLIC_MANAGEDURL_HOST=${PUBLIC_MANAGEDURL_HOST} -e PUBLIC_MANAGEDURL_PORT=${PUBLIC_MANAGEDURL_PORT} \
		-e REDIS_HOST=${REDIS_HOST} -e REDIS_PORT=${REDIS_PORT} -e REDIS_PASS=${REDIS_PASS} \
		-e TOKEN_GOOGLE_URL=https://www.googleapis.com/oauth2/v3/tokeninfo \
	 	-e TOKEN_FACEBOOK_URL=https://graph.facebook.com/debug_token \
		-e TOKEN_GITHUB_URL=https://api.github.com/user \
		-e SNAPSHOTTING=true \
		openwhisk/apigateway:latest

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
			openwhisk/apigateway:latest ${DOCKER_ARGS}

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
