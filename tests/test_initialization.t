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

# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/lib/?.lua;;";
#    init_by_lua '
#        local v = require "jit.v"
#        v.on("$Test::Nginx::Util::ErrLogFile")
#        require "resty.core"
#    ';
    include /etc/api-gateway/conf.d/*.conf;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: check that JIT is enabled
--- http_config eval: $::HttpConfig
--- config
    location /jitcheck {
        content_by_lua '
            if jit then
                ngx.say(jit.version);
            else
                ngx.say("JIT Not Enabled");
            end
        ';
    }
--- request
GET /jitcheck
--- response_body_like eval
["LuaJIT 2.1.0-alpha"]
--- no_error_log
[error]

=== TEST 2: check health-check page
--- http_config eval: $::HttpConfig
--- config
    location /health-check {
        access_log off;
            # MIME type determined by default_type:
            default_type 'text/plain';

            content_by_lua "ngx.say('API-Platform is running!')";
    }
--- request
GET /health-check
--- response_body_like eval
["API-Platform in running!"]
--- no_error_log
[error]

=== TEST 3: check nginx_status is enabled
--- http_config eval: $::HttpConfig
--- config
    location /nginx_status {
            stub_status on;
            access_log   off;
            allow 127.0.0.1;
            deny all;
    }
--- request
GET /nginx_status
--- response_body_like eval
["Active connections: 1"]
--- no_error_log
[error]

