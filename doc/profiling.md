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

# Profiling

I've built a docker file to build everything to run the profiling tools. You can read more about using systemtap++ [here](http://github.com/openresty/stapxx)

Note because this relies on hooking into the linux kernel, this will run in docker ONLY on an ubuntu docker host system.. We need to be able to pull in the kernel headers for the current kernel version.

## Example
### Generating a Lua flamegraph:

Build the docker image:
`make profile-build`

Run the docker image detached:
`make profile-run REDIS_HOST=172.17.0.1 REDIS_PORT=6379`

Attach to the docker image:

```
$ docker ps
CONTAINER ID        IMAGE                                   COMMAND                  CREATED             STATUS              PORTS                                                                           NAMES
939556284e96        openwhisk/apigateway-profiling:latest   "/usr/local/bin/du..."   2 seconds ago       Up 2 seconds        0.0.0.0:80->80/tcp, 0.0.0.0:9000->9000/tcp, 8423/tcp, 0.0.0.0:32772->8080/tcp   apigateway
928d33b75285        redis                                   "docker-entrypoint..."   23 minutes ago      Up 23 minutes       0.0.0.0:6379->6379/tcp                                                          nifty_sinoussi
$ docker exec -ti 9395 /bin/bash
```

Figure out the pid of the nginx worker process:

```
# ps aux
# ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0    200     4 ?        Ss   15:19   0:00 /usr/local/bin/dumb-init -- /etc/init-container.sh
root         7  0.0  0.0  18048  2824 ?        Ss   15:19   0:00 /bin/bash /etc/init-container.sh
root        14  0.0  0.1 195908  8344 ?        S    15:19   0:00 nginx: master process api-gateway -p /usr/local/api-gateway/ -c /etc/api-gateway/api-gateway.
root        16  0.0  0.1 202704 12500 ?        S    15:19   0:00 nginx: worker process
root        17  0.0  0.0   4412   684 ?        S    15:19   0:00 tail -f /var/log/api-gateway/access.log -f /var/log/api-gateway/error.log -f /var/log/api-gat
root        18  0.0  0.0  18252  3348 ?        Ss   15:21   0:00 /bin/bash
root        36  0.0  0.0  34424  2712 ?        R+   15:21   0:00 ps aux
````

Run the profiling tool:

Note during this step you need to be running traffic through the gateway so that lua code is actually being called. This command will get stack traces of whatever lua code is executed at the time this code is run.

```
# ./stap++ samples/lj-lua-stacks.sxx -x 16 --arg time=5 --skip-badvars > a.bt

```

Run the flamegraph generation tool:

```
# ./stackcollapse-stap.pl a.bt > a.cbt
# ./flamegraph.pl --encoding="ISO-8859-1" \
        --title="Lua-land on-CPU flamegraph" \
        a.cbt > a.svg
```

Copy the SVG out of the docker container:

```
# cp a.svg /
# exit
$ docker cp 939556284e96:/a.svg .
```
