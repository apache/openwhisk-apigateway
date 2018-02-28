#!/bin/sh
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

# Install global dependencies
luarocks install busted
luarocks install luacov
# Install test dependencies
mkdir -p lua_modules
luarocks install --tree=lua_modules lua-cjson
luarocks install --tree=lua_modules luabitop
luarocks install --tree=lua_modules luasocket
luarocks install --tree=lua_modules sha1
luarocks install --tree=lua_modules md5
luarocks install --tree=lua_modules net-url
luarocks install --tree=lua_modules luafilesystem