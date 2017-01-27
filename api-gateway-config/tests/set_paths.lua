-- add lua_modules to package.path and package.cpath
local version = _VERSION:match("%d+%.%d+")
local f = assert(io.popen('pwd', 'r'))
local pwd = assert(f:read('*a')):sub(1, -2)
f:close()
package.path = package.path ..
    ';' .. pwd .. '/lua_modules/share/lua/' .. version .. '/?.lua' ..
    ';' .. pwd .. '/lua_modules/share/lua/' .. version .. '/?/init.lua' ..
    ';' .. pwd .. '/lua_modules/share/lua/' .. version .. '/net/?.lua' ..
    ';' .. pwd .. '/../scripts/lua/?.lua'
package.cpath = package.cpath ..
    ';' .. pwd .. '/lua_modules/lib/lua/' .. version .. '/?.so'