local cjson = require "cjson"

local _M = {}

--- Initialize and connect to Redis
-- @param host
-- @param port
-- @param ngx
function _M.init(host, port, ngx)
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

--- Add current redis connection in the ngx_lua cosocket connection pool
-- @param red
-- @param ngx
function _M.close(red, ngx)
    -- put it into the connection pool of size 100, with 10 seconds max idle time
    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        ngx.status(500)
        ngx.say("failed to set keepalive: ", err)
        ngx.exit(ngx.status)
    end
end

--- Generate Redis object for route
-- @param red
-- @param key
-- @param gatewayMethod
-- @param backendUrl
-- @param backendMethod
-- @param policies
-- @param ngx
function _M.generateRouteObj(red, key, gatewayMethod, backendUrl, backendMethod, policies, ngx)
    local routeObj = _M.getRoute(red, key, "route", ngx)
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
-- @param ngx
function _M.createRoute(red, key, field, routeObj, ngx)
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
-- @param ngx
-- @return routeObj
function _M.getRoute(red, key, field, ngx)
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
-- @param ngx
function _M.deleteRoute(red, key, field, ngx)
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

return _M
