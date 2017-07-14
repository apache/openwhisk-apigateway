#
#  Figure out a few of the environmental aspects of docker
#
DOCKER_ARCH = $(shell sh -c "docker info 2>/dev/null | sed -n -e 's/^Architecture: \(.*\)/\1/p'")
DOCKER_KERNEL_VERSION = $(shell sh -c "docker info 2>/dev/null | sed -n -e 's/^Kernel Version: \([^-]*\).*/\1/p'")
DOCKER_KERNEL_MAJOR = $(shell sh -c "docker info 2>/dev/null | sed -n -e 's/^Kernel Version: \([0-9]*\).*/\1/p'")

#
#  Default tags.  To override for a given run, use 'DOCKER_TAG=mytag make ...'
#
DOCKER_RUN_TAG = openwhisk/apigateway:latest
DOCKER_PROFILE_TAG = openwhisk/apigateway-profiling:latest

#  Architecture-dependent manipulations of the Dockerfile
#
#  Note:  The variables don't bind until execution time, so the default
#         for DOCKER_DISTRO is set below in 'docker' and 'profile-build'
#         and could be set for other build steps.
ifeq "$(DOCKER_ARCH)" "s390x"
SEDCMD = s!^FROM \(alpine\|ubuntu\):!FROM $(DOCKER_ARCH)/$(DOCKER_DISTRO):!
else
SEDCMD = s!^FROM \(alpine\|ubuntu\):!FROM $(DOCKER_DISTRO):!
endif

docker/Dockerfile.generated: docker/Dockerfile
	sed -e '$(SEDCMD)' <docker/Dockerfile >docker/Dockerfile.generated

.PHONY: docker
docker: DOCKER_DISTRO ?= alpine
docker: DOCKER_TAG ?= $(DOCKER_RUN_TAG)
docker: docker/Dockerfile.generated
	cd docker && docker build -t $(DOCKER_TAG) --build-arg DISTRO=$(DOCKER_DISTRO) -f Dockerfile.generated .

.PHONY: docker-ssh
docker-ssh: DOCKER_TAG ?= $(DOCKER_RUN_TAG)
docker-ssh:
	cd docker && docker run -ti --entrypoint='bash' $(DOCKER_TAG)

.PHONY: test-build
test-build:
	cd tests; ./install-deps.sh

.PHONY: profile-build
profile-build: DOCKER_DISTRO ?= ubuntu
profile-build: DOCKER_TAG ?= $(DOCKER_PROFILE_TAG)
profile-build:
	cd docker \
	&& sed -e 's/worker_processes\ *auto;/worker_processes\ 1;/g' etc-api-gateway/api-gateway.conf > ./api-gateway.conf.profiling \
	&& sed -e '$(SEDCMD)' -e 's/^#PROFILE //' Dockerfile > Dockerfile.profiling \
	&& docker build --build-arg PROFILE=yes --build-arg DISTRO=$(DOCKER_DISTRO) \
			-t $(DOCKER_TAG) -f Dockerfile.profiling .

#
#  Download kernel source for the current Docker kernel in support of
#  profiling
#
kernel-src/linux-$(DOCKER_KERNEL_VERSION):
		echo $(DOCKER_KERNEL_VERSION); \
		mkdir -p kernel-src; \
    curl -L \
			"https://cdn.kernel.org/pub/linux/kernel/v$(DOCKER_KERNEL_MAJOR).x/linux-$(DOCKER_KERNEL_VERSION).tar.gz" \
			| tar zfx - -C kernel-src

.PHONY: profile-run
profile-run: DOCKER_TAG ?= $(DOCKER_PROFILE_TAG)
profile-run: profile-build kernel-src/linux-$(DOCKER_KERNEL_VERSION)
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
		-v `pwd`/kernel-src:/usr/src \
		$(DOCKER_TAG)

.PHONY: test-run
test-run:
	cd tests; ./run-tests.sh

.PHONY: docker-run
docker-run: DOCKER_TAG ?= $(DOCKER_RUN_TAG)
docker-run:
	docker run --rm --name="apigateway" -p 80:80 -p ${PUBLIC_MANAGEDURL_PORT}:8080 -p 9000:9000 \
		-e PUBLIC_MANAGEDURL_HOST=${PUBLIC_MANAGEDURL_HOST} -e PUBLIC_MANAGEDURL_PORT=${PUBLIC_MANAGEDURL_PORT} \
		-e REDIS_HOST=${REDIS_HOST} -e REDIS_PORT=${REDIS_PORT} -e REDIS_PASS=${REDIS_PASS} \
		-e TOKEN_GOOGLE_URL=https://www.googleapis.com/oauth2/v3/tokeninfo \
	 	-e TOKEN_FACEBOOK_URL=https://graph.facebook.com/debug_token \
		-e TOKEN_GITHUB_URL=https://api.github.com/user \
		-e APPID_PKURL=https://appid-oauth.ng.bluemix.net/oauth/v3/ \
		-e LD_LIBRARY_PATH=/usr/local/lib \
		$(DOCKER_TAG)

.PHONY: docker-debug
docker-debug: DOCKER_TAG ?= $(DOCKER_RUN_TAG)
docker-debug:
	#Volumes directories must be under your Users directory
	mkdir -p ${HOME}/tmp/apiplatform/apigateway
	rm -rf ${HOME}/tmp/apiplatform/apigateway
	cp -r `pwd` ${HOME}/tmp/apiplatform/apigateway/
	docker run --name="apigateway" \
			-p 80:80 -p 5000:5000 \
			-e "LOG_LEVEL=info" -e "DEBUG=true" \
			-v ${HOME}/tmp/apiplatform/apigateway/:/etc/api-gateway \
			$(DOCKER_TAG) ${DOCKER_ARGS}

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
	rm -f docker/Dockerfile.generated docker/Dockerfile.profiling \
		docker/api-gateway.conf.profiling* kernel-src/*
