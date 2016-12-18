#!/bin/bash
#/*
# * Copyright (c) 2012 Adobe Systems Incorporated. All rights reserved.
# *
# * Permission is hereby granted, free of charge, to any person obtaining a
# * copy of this software and associated documentation files (the "Software"),
# * to deal in the Software without restriction, including without limitation
# * the rights to use, copy, modify, merge, publish, distribute, sublicense,
# * and/or sell copies of the Software, and to permit persons to whom the
# * Software is furnished to do so, subject to the following conditions:
# *
# * The above copyright notice and this permission notice shall be included in
# * all copies or substantial portions of the Software.
# *
# * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# * DEALINGS IN THE SOFTWARE.
# *
# */
debug_mode=${DEBUG}
log_level=${LOG_LEVEL:-warn}
marathon_host=${MARATHON_HOST}
redis_host=${REDIS_HOST}
redis_port=${REDIS_PORT}
sleep_duration=${MARATHON_POLL_INTERVAL:-5}
# location for a remote /etc/api-gateway folder.
# i.e s3://api-gateway-config
remote_config=${REMOTE_CONFIG}
remote_config_sync_interval=${REMOTE_CONFIG_SYNC_INTERVAL:-10s}

echo "Starting api-gateway ..."
if [ "${debug_mode}" == "true" ]; then
    echo "   ...  in DEBUG mode "
    mv /usr/local/sbin/api-gateway /usr/local/sbin/api-gateway-no-debug
    ln -sf /usr/local/sbin/api-gateway-debug /usr/local/sbin/api-gateway
fi

/usr/local/sbin/api-gateway -V
echo "------"

echo resolver $(awk 'BEGIN{ORS=" "} /nameserver/{print $2}' /etc/resolv.conf | sed "s/ $/;/g") > /etc/api-gateway/conf.d/includes/resolvers.conf
echo "   ...  with dns $(cat /etc/api-gateway/conf.d/includes/resolvers.conf)"

echo "   ... testing configuration "
api-gateway -t -p /usr/local/api-gateway/ -c /etc/api-gateway/api-gateway.conf

echo "   ... using log level: '${log_level}'. Override it with -e 'LOG_LEVEL=<level>' "
api-gateway -p /usr/local/api-gateway/ -c /etc/api-gateway/api-gateway.conf -g "daemon off; error_log /dev/stderr ${log_level};" &

if [[ -n "${redis_host}" && -n "${redis_port}" ]]; then
    sleep 1  # sleep until api-gateway is set up
    tail -f /var/log/api-gateway/access.log -f /var/log/api-gateway/error.log \
         -f /var/log/api-gateway/gateway_error.log -f /var/log/api-gateway/management.log &
    curl -s http://0.0.0.0:9000/v1/subscribe # subscribe to redis key changes for routes
else
    echo "REDIS_HOST and/or REDIS_PORT not defined"
fi


