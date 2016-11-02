#!/bin/bash

# Install global dependencies
luarocks install busted
luarocks install luacov
# Install test dependencies
mkdir -p lua_modules
luarocks install --tree lua_modules lua-cjson
luarocks install --tree lua_modules luabitop
luarocks install --tree lua_modules luasocket
luarocks install --tree lua_modules sha1
luarocks install --tree lua_modules md5
luarocks install --tree lua_modules fakeredis