<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for additional
# information regarding copyright ownership.  The ASF licenses this file to you
# under the Apache License, Version 2.0 (the # "License"); you may not use this
# file except in compliance with the License.  You may obtain a copy of the License
# at:
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
-->

OpenWhisk API Gateway
=============
[![Build Status](https://travis-ci.org/apache/incubator-openwhisk-apigateway.svg?branch=master)](https://travis-ci.org/apache/incubator-openwhisk-apigateway)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

A performant API Gateway based on Openresty and NGINX.

Project status
---------------
This project is currently considered beta stage, Large swaths of code or APIs may change.


## Table of Contents

* [Quick Start](#quick-start)
* [API](#api)
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

## API
- [v2 Management Interface](https://github.com/openwhisk/openwhisk-apigateway/blob/master/doc/v2/management_interface_v2.md)
- [v1 Management Interface](https://github.com/openwhisk/openwhisk-apigateway/blob/master/doc/v1/management_interface_v1.md)


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
