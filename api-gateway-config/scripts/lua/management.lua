local cjson = require "cjson"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")

local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local _M = {}


--- Add/update a route to redis and create/update an nginx conf file given PUT JSON body
-- 
-- PUT http://0.0.0.0:9000/routes/<namespace>/<url-encoded-route>
-- Example PUT JSON body:
-- { 
--      "gatewayMethod": "GET", 
--      "backendURL": "http://openwhisk.ng.bluemix.net/guest/action?blocking=true", 
--      "backendMethod": "POST", 
--      "policies": []
--  }
--
function _M.addRoute()
    -- Read in the PUT JSON Body
    ngx.req.read_body()
    local args = ngx.req.get_post_args()
    if not args then
        ngx.status = 400
        ngx.say("Error: missing request body")
        ngx.exit(ngx.status)
    end
    -- Convert json into Lua table
    local decoded = convertJSONBody(args)

    -- Error handling for correct fields in the request body
    local gatewayMethod = decoded.gatewayMethod
    if not gatewayMethod then
        ngx.status = 400
        ngx.say("Error: \"gatewayMethod\" missing from request body.")
        ngx.exit(ngx.status)
    end
    local policies = decoded.policies
    if not policies then
        ngx.status = 400
        ngx.say("Error: \"policies\" missing from request body.")
        ngx.exit(ngx.status)
    end
    local backendUrl = decoded.backendURL
    if not backendUrl then
        ngx.status = 400
        ngx.say("Error: \"backendURL\" missing from request body.")
        ngx.exit(ngx.status)
    end
    -- Use gatewayMethod by default or usebackendMethod if specified
    local backendMethod = decoded and decoded.backendMethod or gatewayMethod

    local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
    local redisKey, namespace, gatewayPath = parseRequestURI(requestURI)
    
    -- Open connection to redis or use one from connection pool
    local red = initRedis(REDIS_HOST, REDIS_PORT)
    
    local routeObj = generateRouteObj(red, redisKey, gatewayMethod, backendUrl, backendMethod, policies)
    createRedisRoute(red, redisKey, "route", routeObj)
    createRouteConf(namespace, gatewayPath, routeObj, backendUrl)

    -- Add current redis connection in the ngx_lua cosocket connection pool
    closeRedis(red)

    ngx.status = 200
    ngx.say(routeObj)
    ngx.exit(ngx.status)
end


--- Get route from redis 
--
-- Use optional query parameter, verb, to specify the verb of the route to get
-- Default behavior is to get all the verbs for that route
--
-- GET http://0.0.0.0:9000/routes/<namespace>/<url-encoded-route>?verb="<verb>"
-- 
function _M.getRoute()
    local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
    local redisKey = parseRequestURI(requestURI)
    
    -- Initialize and connect to redis
    local red = initRedis(REDIS_HOST, REDIS_PORT)
    
    local routeObj = getRedisRoute(red, redisKey, "route")
    if routeObj == nil then
        ngx.status = 404
        ngx.say("Route doesn't exist.")
        ngx.exit(ngx.status)
    end

    -- Add current redis connection in the ngx_lua cosocket connection pool
    closeRedis(red)

    ngx.status = 200
    ngx.say(routeObj)
    ngx.exit(ngx.status)
end


--- Delete route from redis
-- 
-- DELETE http://0.0.0.0:9000/routes/<namespace>/<url-encoded-route>
--
function _M.deleteRoute()
    local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
    local redisKey, namespace, gatewayPath = parseRequestURI(requestURI)

    -- Initialize and connect to redis
    local red = initRedis(REDIS_HOST, REDIS_PORT)

    -- Return if route doesn't exist
    deleteRedisRoute(red, redisKey, "route")
    
    -- Delete conf file
    os.execute(concatStrings({"rm -f ", BASE_CONF_DIR, namespace, "/", gatewayPath, ".conf"}))
    
    -- Add current redis connection in the ngx_lua cosocket connection pool
    closeRedis(red)

    ngx.status = 200
    ngx.say("Route deleted.")
    ngx.exit(ngx.status) 
end

--- Subscribe to redis
function _M.subscribe() 
    -- Initialize and connect to redis
    local red = initRedis(REDIS_HOST, REDIS_PORT)

    local ok, err = red:subscribe("routes")
    if not ok then
        ngx.say("subscribe error: ", err)
        return
    end
    ngx.say("Subscribed to channel routes")
    while(true) do
        res, err = red:read_reply()
        if not res then
            ngx.say("Failed to read reply: ", err)
        else
            ngx.say(cjson.encode(res))
        end
    end
end

--- Unsusbscribe to redis
function _M.unsubscribe()
    -- Initialize and connect to redis
    local red = initRedis(REDIS_HOST, REDIS_PORT)

    local ok, err = red:unsubscribe("routes")
    if not ok then
        ngx.say("unsubscribe error: ", err)
        return
    end
    ngx.say(ok)
    ngx.say("Unsusbscribed to channel routes")
end


--- Initialize and connect to Redis
function initRedis(host, port)
    local redis = require "resty.redis"
    local red   = redis:new()
    red:set_timeout(1000)
    
    -- Connect to Redis server
    local connect, err = red:connect(host, port)
    if not connect then
        ngx.status(500)
        ngx.say("Failed to connect to redis: " .. err)
        ngx.exit(ngx.status)
    end

    return red
end

--- Parse the request uri to get the redisKey, namespace, and gatewayPath
-- @param requestURI
-- @return redisKey, namespace, gatewayPath
function parseRequestURI(requestURI)
    local index = 0
    local prefix = nil
    local namespace = nil
    local gatewayPath = nil
    for word in string.gmatch(requestURI, '([^/]+)') do
        -- word is "routes"
        if index == 0 then
            prefix = word
        -- word is the namespace
        elseif index == 1 then
            namespace = word
        -- the rest is the path
        elseif index == 2 then
            gatewayPath = word
        end
        index = index + 1
    end
    if not namespace or not gatewayPath or index > 3 then
        ngx.status = 400
        ngx.say("Error: Request path should be \"/routes/<namespace>/<url-encoded-route>\"")
        ngx.exit(ngx.status)
    end

    local redisKey = concatStrings({prefix, ":", namespace, ":", gatewayPath})
    return redisKey, namespace, gatewayPath
end

--- Generate Redis object for route
-- @param red
-- @param key
-- @param gatewayMethod
-- @param backendUrl
-- @param backendMethod
-- @param policies
function generateRouteObj(red, key, gatewayMethod, backendUrl, backendMethod, policies)
    local routeObj = getRedisRoute(red, key, "route")
    if routeObj == nil then
        local newRoute = {
	        [gatewayMethod] = {
                backendUrl    = backendUrl,
                backendMethod = backendMethod,
                policies      = policies
            }
        }
        return cjson.encode(newRoute)
    else
        local decoded = cjson.decode(routeObj)
        decoded[gatewayMethod] = {
            backendUrl    = backendUrl,
            backendMethod = backendMethod,
            policies      = policies
        }
        return cjson.encode(decoded)
    end
end

--- Create/update route in redis
-- @param red
-- @param key
-- @param field
-- @param routeObj
function createRedisRoute(red, key, field, routeObj)
    -- Add/update route to redis
    local ok, err = red:hset(key, field, routeObj)
    if not ok then
        ngx.status(500)
        ngx.say("Failed adding Route to redis: " .. err)
        ngx.exit(ngx.status)
    end
end

--- Get route in redis
-- @param red
-- @param key
-- @param field
-- @return routeObj
function getRedisRoute(red, key, field)
    local routeObj, err = red:hget(key, field)
    if not routeObj then
        ngx.status(500)
        ngx.say("Error getting route: ", err)
        ngx.exit(ngx.statis)
    end
   
    -- return nil if route doesn't exist
    if routeObj == ngx.null then
        return nil
    end

    -- Get routeObj from redis using redisKey
    local args = ngx.req.get_uri_args()
    local requestVerb = nil
    for k, v in pairs(args) do 
        if k == "verb" then
            requestVerb = v
        end
    end

    if requestVerb == nil then 
        return routeObj
    else
        routeObj = cjson.decode(routeObj)
        return cjson.encode(routeObj[requestVerb]) 
    end
end

--- Delete route int redis
-- @param red
-- @param key
-- @param field
function deleteRedisRoute(red, key, field)
    local routeObj, err = red:hget(key, field)
    if not routeObj then
        ngx.status(500)
        ngx.say("Error deleting route: ", err)
        ngx.exit(ngx.status)
    end
    
    if routeObj == ngx.null then
        ngx.status(404)
        ngx.say("Route doesn't exist.")
        ngx.exit(ngx.status)
    end

    local ok, err = red:del(key)
    if not ok then
        ngx.status(500)
        ngx.say("Error deleing route: ", err)
        ngx.exit(ngx.status)
    end
end

--- Create/overwrite Nginx Conf file for given route
-- @param namespace
-- @param gatewayPath
-- @param routeObj
-- @param backendUrl
function createRouteConf(namespace, gatewayPath, routeObj, backendUrl)
    -- Set rotue headers and mapping by calling routing.processCall()
    local outgoingRoute = concatStrings({"\t",   "access_by_lua '",                       "\n",
                                         "\t\t", "local routing = require \"routing\"",   "\n",
                                         "\t\t", "local whisk   = require \"whisk\"",     "\n",
                                         "\t\t", "routing.processCall({", routeObj, "})", "\n",
                                         "\t",   "';",                                    "\n"})

    -- set proxy_pass with upstream
    local proxyPass = concatStrings({"\tproxy_pass ", backendUrl, ";\n"})

    -- Add to endpoint conf file
    os.execute(concatStrings({"mkdir -p ", BASE_CONF_DIR, namespace}))
    local file, err = io.open(concatStrings({BASE_CONF_DIR, namespace, "/", gatewayPath, ".conf"}), "w")
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

--- Initialize and connect to Redis
function initRedis(host, port)
    local redis = require "resty.redis"
    local red   = redis:new()
    red:set_timeout(1000)

    -- Connect to Redis server
    local connect, err = red:connect(host, port)
    if not connect then
        ngx.status(500)
        ngx.say("Failed to connect to redis: " .. err)
        ngx.exit(ngx.status)
    else
        return red
    end
end

--- Add current redis connection in the ngx_lua cosocket connection pool
-- @param red
function closeRedis(red)
    -- put it into the connection pool of size 100, with 10 seconds max idle time
    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        ngx.status(500)
        ngx.say("failed to set keepalive: ", err)
        ngx.exit(ngx.status)
    end
end

--- Convert JSON body to Lua table using the cjson module
-- @param args
function convertJSONBody(args)
    local decoded = nil
    local jsonStringList = {}
    for key, value in pairs(args) do
	table.insert(jsonStringList, key)
        -- Handle case where the "=" character is inside any of the strings in the json body
        if(value ~= true) then
            table.insert(jsonStringList, "=" .. value)
        end
    end
    return cjson.decode(concatStrings(jsonStringList))
end

--- Concatenate a list of strings into a single string. This is more efficient than concatenating
-- strings together with "..", which creates a new string every time
-- @param list List of strings to concatenate
-- @return concatenated string
function concatStrings(list)
    local t = {}
    for k,v in ipairs(list) do
        t[#t+1] = tostring(v)
    end
    return table.concat(t)
end


return _M
