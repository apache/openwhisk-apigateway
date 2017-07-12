DOCKER_TAG ?= snapshot-`date +'%Y%m%d-%H%M'`
DOCKER_REGISTRY ?= ''
DOCKER_ARCH = $(shell sh -c "docker info 2>/dev/null | sed -n -e 's/Architecture: \(.*\)/\1/p'")

#  Architecture-dependent manipulations of the Dockerfile
#
#  Note:  The variables don't bind until execution time, so the default
#         for DOCKER_DISTRO is set below in 'docker' and 'profile-build'
#         and could be set for other build steps.
ifeq "$(DOCKER_ARCH)" "s390x"
SEDCMD=s!^FROM \(alpine\|ubuntu\):!FROM $(DOCKER_ARCH)/$(DOCKER_DISTRO):!
else
SEDCMD=s!^FROM \(alpine\|ubuntu\):!FROM $(DOCKER_DISTRO):!
endif

Dockerfile.generated: Dockerfile
	sed -e '$(SEDCMD)' <Dockerfile >Dockerfile.generated

.PHONY: docker
docker: DOCKER_DISTRO ?= alpine
docker: Dockerfile.generated
	docker build -t openwhisk/apigateway --build-arg DISTRO=$(DOCKER_DISTRO) -f Dockerfile.generated .

.PHONY: docker-ssh
docker-ssh:
	docker run -ti --entrypoint='bash' openwhisk/apigateway:latest

.PHONY: test-build
test-build:
	cd tests; ./install-deps.sh

# TODO: Integrate the architecture changes into the profiling
.PHONY: profile-build
profile-build: DOCKER_DISTRO ?= ubuntu
profile-build:
	sed -e 's/worker_processes\ *auto;/worker_processes\ 1;/g' api-gateway.conf > api-gateway.conf.profiling
	sed -e '$(SEDCMD)' -e 's/^#PROFILE //' Dockerfile > Dockerfile.profiling
	docker build --build-arg PROFILE=yes --build-arg DISTRO=$(DOCKER_DISTRO) \
			-t openwhisk/apigateway-profiling -f Dockerfile.profiling .

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
		openwhisk/apigateway-profiling:latest

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
		-e APPID_PKURL=https://appid-oauth.ng.bluemix.net/oauth/v3/ \
		-e LD_LIBRARY_PATH=/usr/local/lib \
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

.PHONY: clean
clean:
	rm -f Dockerfile.generated Dockerfile.profiling api-gateway.conf.profile*
