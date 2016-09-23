local utils = require "lib/utils"

local _M = {}

--- Create/overwrite Nginx Conf file for given route
-- @param baseConfDir
-- @param namespace
-- @param gatewayPath
-- @param routeObj
function _M.createRouteConf(baseConfDir, namespace, gatewayPath, routeObj)
    local prefix = utils.concatStrings({"\t", "include /etc/api-gateway/conf.d/commons/common-headers.conf;", "\n",
                                        "\t", "set $upstream https://172.17.0.1;", "\n\n"})
    -- Set rotue headers and mapping by calling routing.processCall()
    local outgoingRoute = utils.concatStrings({"\t",   "access_by_lua_block {",                   "\n",
                                               "\t\t", "local routing = require \"routing\"",     "\n",
                                               "\t\t", "local whisk   = require \"whisk\"",       "\n",
                                               "\t\t", "routing.processCall({'", routeObj, "'})", "\n",
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
