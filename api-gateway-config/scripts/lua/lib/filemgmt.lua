
local _M = {}

--- Create/overwrite Nginx Conf file for given route
-- @param baseConfDir
-- @param namespace
-- @param gatewayPath
-- @param routeObj
-- @param backendUrl
function _M.createRouteConf(baseConfDir, namespace, gatewayPath, routeObj, backendUrl)
    -- Set rotue headers and mapping by calling routing.processCall()
    local outgoingRoute = concatStrings({"\t",   "access_by_lua '",                       "\n",
                                         "\t\t", "local routing = require \"routing\"",   "\n",
                                         "\t\t", "local whisk   = require \"whisk\"",     "\n",
                                         "\t\t", "routing.processCall({", routeObj, "})", "\n",
                                         "\t",   "';",                                    "\n"})

    -- set proxy_pass with upstream
    local proxyPass = concatStrings({"\tproxy_pass ", backendUrl, ";\n"})

    -- Add to endpoint conf file
    os.execute(concatStrings({"mkdir -p ", baseConfDir, namespace}))
    local file, err = io.open(concatStrings({baseConfDir, namespace, "/", gatewayPath, ".conf"}), "w")
    if not file then
        ngx.status(500)
        ngx.say("Error adding to endpoint conf file: " .. err)
        ngx.exit(ngx.status)
    end
    local location = concatStrings({"location /api/", namespace, "/", gatewayPath, " {\n",
                                    outgoingRoute,
                                    proxyPass,
                                    "}\n"})
    file:write(location .. "\n")
    file:close()
end

--- Delete Ngx conf file for given route
function _M.deleteRouteConf(baseConfDir, namespace, gatewayPath)
    os.execute(concatStrings({"rm -f ", baseConfDir, namespace, "/", gatewayPath, ".conf"}))
end

return _M
