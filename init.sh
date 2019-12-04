#!/bin/bash
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

debug_mode=${DEBUG}
log_level=${LOG_LEVEL:-warn}
marathon_host=${MARATHON_HOST}
redis_host=${REDIS_HOST}
redis_port=${REDIS_PORT}
if [ "${DECRYPT_REDIS_PASS}" == "true" ]; then
    export REDIS_PASS=$(printf "${REDIS_PASS}\n" | openssl enc -d -K ${ENCRYPTION_KEY} -iv ${ENCRYPTION_IV} -aes-256-cbc -base64)
fi

sleep_duration=${MARATHON_POLL_INTERVAL:-5}
# location for a remote /etc/api-gateway folder.
# i.e s3://api-gateway-config
remote_config=${REMOTE_CONFIG}
remote_config_sync_interval=${REMOTE_CONFIG_SYNC_INTERVAL:-10s}
remote_config_reload_cmd=${REMOTE_CONFIG_RELOAD_CMD:-api-gateway -s reload}

echo "Starting api-gateway ..."
if [ "${debug_mode}" == "true" ]; then
    echo "   ...  in DEBUG mode "
    mv /usr/local/sbin/api-gateway /usr/local/sbin/api-gateway-no-debug
    ln -sf /usr/local/sbin/api-gateway-debug /usr/local/sbin/api-gateway
fi

/usr/local/sbin/api-gateway -V
echo "------"

sync_cmd="echo ''" # when left empty, the config supervisor would only watch /etc/api-gateway for changes
if [[ -n "${remote_config}" ]]; then
    echo "   ... using configuration from: ${remote_config}"
    sync_cmd="rclone sync ${remote_config} /etc/api-gateway/"
fi

api-gateway-config-supervisor \
    --reload-cmd="${remote_config_reload_cmd}" \
    --sync-folder=/etc/api-gateway \
    --sync-interval=${remote_config_sync_interval} \
    --sync-cmd="${sync_cmd}" \
    --http-addr=127.0.0.1:8888 &

echo resolver $(awk 'BEGIN{ORS=" "} /^nameserver/{print $2}' /etc/resolv.conf | sed "s/ $/ ipv6=off;/g") > /etc/api-gateway/conf.d/includes/resolvers.conf
echo "   ...  with dns $(cat /etc/api-gateway/conf.d/includes/resolvers.conf)"

echo "   ... testing configuration "
api-gateway -t -p /usr/local/api-gateway/ -c /etc/api-gateway/api-gateway.conf

echo "   ... using log level: '${log_level}'. Override it with -e 'LOG_LEVEL=<level>' "
api-gateway -p /usr/local/api-gateway/ -c /etc/api-gateway/api-gateway.conf -g "daemon off; error_log /dev/stderr ${log_level};" &

if [[ -n "${redis_host}" && -n "${redis_port}" ]]; then
    sleep 1  # sleep until api-gateway is set up
    tail -f /var/log/api-gateway/access.log -f /var/log/api-gateway/error.log \
         -f /var/log/api-gateway/gateway_error.log -f /var/log/api-gateway/management.log
else
    echo "REDIS_HOST and/or REDIS_PORT not defined"
fi
