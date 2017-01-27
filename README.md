apigateway
=============
[![Build Status](https://travis-ci.org/openwhisk/apigateway.svg?branch=master)](https://travis-ci.org/openwhisk/apigateway)

A performant API Gateway based on Openresty and NGINX.

Project status
---------------
This project is currently considered pre-alpha stage, and should not be used in production. Large swaths of code or APIs may change without notice.


## Table of Contents

* [Quick Start](#quick-start)
* [Routes](#routes)
* [Developer Guide](#developer-guide)
  * [Running locally](#running-locally)
  * [Testing](#testing)


## Quick Start

```
docker run -p 80:80 -p <managedurl_port>:8080 -p 9000:9000 \
            -e PUBLIC_MANAGEDURL_HOST=<managedurl_host> \
            -e PUBLIC_MANAGEDURL_PORT=<managedurl_port> \
            -e REDIS_HOST=<redis_host> \
            -e REDIS_PORT=<redis_port> \
            -e REDIS_PASS=<redis_pass> \
            openwhisk/apigateway:latest
```

This command starts an API Gateway that subscribes to the Redis instance with the specified host and port. The `REDIS_PASS` variable is optional and is required only when redis needs authentication. 

On startup, the API Gateway subscribes to redis and listens for changes in keys that are defined as `resources:<namespace>:<resourcePath>`.

## Routes
See [here](doc/routes.md) for the management interface for creating tenants/APIs. For detailed API policy definitions, see [here](doc/policies.md).


## Developer Guide

### Running locally

 To build the docker image locally use:
 ```
  make docker
 ```

 To Run the Docker image
 ```
  make docker-run PUBLIC_MANAGEDURL_HOST=<mangedurl_host> PUBLIC_MANAGEDURL_PORT=<managedurl_port> \
    REDIS_HOST=<redis_host> REDIS_PORT=<redis_port> REDIS_PASS=<redis_pass>
 ```

 
### Testing

 First install the necessary dependencies:
 ```
  make test-build
 ```
 Then, run the unit tests:
 ```
  make test-run
 ```

