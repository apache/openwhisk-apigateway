-- Copyright (c) 2016 IBM. All rights reserved.
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the "Software"),
--   to deal in the Software without restriction, including without limitation
--   the rights to use, copy, modify, merge, publish, distribute, sublicense,
--   and/or sell copies of the Software, and to permit persons to whom the
--   Software is furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in
--   all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
--   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
--   DEALINGS IN THE SOFTWARE.

--- @module
--
-- @author Alex Song (songs)

local utils = require "lib/utils"
local cjson = require "cjson"

local _M = {}

--- Create/overwrite Nginx Conf file for given route
-- @param baseConfDir
-- @param namespace
-- @param gatewayPath
-- @param routeObj
function _M.createRouteConf(baseConfDir, namespace, gatewayPath, routeObj)
    routeObj = utils.serializeTable(cjson.decode(routeObj))
    local prefix = utils.concatStrings({"\t", "include /etc/api-gateway/conf.d/commons/common-headers.conf;", "\n",
                                        "\t", "set $upstream https://172.17.0.1;", "\n\n"})
    -- Set route headers and mapping by calling routing.processCall()
    local outgoingRoute = utils.concatStrings({"\t",   "access_by_lua_block {",                   "\n",
                                               "\t\t", "local routing = require \"routing\"",     "\n",
                                               "\t\t", "routing.processCall(", routeObj, ")", "\n",
                                               "\t",   "}",                                       "\n"})

    -- set proxy_pass with upstream
    local proxyPass = utils.concatStrings({"\tproxy_pass $upstream; \n"})

    -- Add to endpoint conf file
    os.execute(utils.concatStrings({"mkdir -p ", baseConfDir, namespace}))
    local file, err = io.open(utils.concatStrings({baseConfDir, namespace, "/", gatewayPath, ".conf"}), "w")
    if not file then
        ngx.status(500)
        ngx.say("Error adding to endpoint conf file: " .. err)
        ngx.exit(ngx.status)
    end
    local location = utils.concatStrings({"location /api/", namespace, "/", gatewayPath, " {\n",
                                          prefix,
                                          outgoingRoute,
                                          proxyPass,
                                          "}\n"})
    file:write(location .. "\n")
    file:close()
end

--- Delete Ngx conf file for given route
function _M.deleteRouteConf(baseConfDir, namespace, gatewayPath)
    os.execute(utils.concatStrings({"rm -f ", baseConfDir, namespace, "/", gatewayPath, ".conf"}))
end

return _M
