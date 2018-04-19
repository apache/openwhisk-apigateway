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

## Syncing configuration from a remote source

The Gateway can sync its configuration with a remote folder in the cloud such as Amazon S3, Google Cloud Storage, IBM Cloud Object Storage, Dropbox, and [many others](https://rclone.org/). The configuration is monitored for changes, and when a file is changed, the Gateway is reloaded automatically. This is very useful to gracefully update the Gateway on the fly, without impacting the active traffic; if the new configuration is invalid, the Gateway doesn't break, running with the last known valid configuration.

This feature is enabled by configuring a few environment variables:
* `REMOTE_CONFIG` - the location where the config should be synced from. I.e. `s3://api-gateway-config` . The remote location is synced into is `/etc/api-gateway`.
* (optional) `REMOTE_CONFIG_SYNC_INTERVAL` - how often to check for changes in the remote location. The default value is `10s`
* (optional) `REMOTE_CONFIG_RELOAD_CMD` - which command to execute in order to reload the Gateway. The default value is: `api-gateway -s reload`

Syncing is done through [rclone sync](https://rclone.org/commands/rclone_sync/). `rclone` has a rich set of [options](https://rclone.org/commands/rclone_sync/) such as what to exclude when syncing, or what to include. An important configuration is `--config`, pointing to the config file in `/root/.config/rclone/rclone.conf`. The Gateway should be started with `/root/.config/rclone` folder mounted so that `rclone.conf` is present.  To generate a new `rclone` configuration simply execute:

```
docker run -ti --rm --entrypoint=rclone -v `pwd`/rclone/:/root/.config/rclone/ openwhisk/apigateway config
```  

This runs an interactive `rclone config` command and stores the resulted configuration in `./rclone/rclone.conf` file.  

To test this locally, _simulate_ a remote folder using a local location, by mounting it in `/tmp` folder as follows:

```bash
docker run -ti --rm -p 80:80  \ 
    -v `pwd`:/tmp/api-gateway-local -e REMOTE_CONFIG="/tmp/api-gateway-local" \
    -e REDIS_HOST=redis_host -e REDIS_PORT=redis_port openwhisk/apigateway
```
Then make changes to any configuration file ( i.e. `api-gateway.conf` ), save it, then watch as the Gateway reloads the updated configuration automatically.

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
