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

local cjson = require "cjson"
local filemgmt = require "lib/filemgmt"
local utils = require "lib/utils"
local logger = require "lib/logger"

local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local _M = {}

--- Initialize and connect to Redis
-- @param host
-- @param port
-- @param password
-- @param timeout
-- @param ngx
function _M.init(host, port, password, timeout, ngx)
    local redis = require "resty.redis"
    local red   = redis:new()
    red:set_timeout(timeout)

    -- Connect to Redis server
    local connect, err = red:connect(host, port)
    if not connect then
        ngx.status = 500
        ngx.say(utils.concatStrings({"Failed to connect to redis: ", err}))
        ngx.exit(ngx.status)
    end

    -- Authenticate with Redis
    if password ~= nil and password ~= "" then
        local res, err = red:auth(password)
        if not res then
            ngx.status = 500
            ngx.say(utils.concatStrings({"Failed to authenticate: ", err}))
            ngx.exit(ngx.status)
        end
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
        ngx.status = 500
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
function _M.generateRouteObj(red, key, gatewayMethod, backendUrl, backendMethod, policies, security, ngx)
    local routeObj = _M.getRoute(red, key, "route", ngx)
    if routeObj == nil then
        local newRoute = {
            [gatewayMethod] = {
                backendUrl    = backendUrl,
                backendMethod = backendMethod,
                policies      = policies,
            }
        }
        if security then
          newRoute[gatewayMethod].security = security
        end
        return cjson.encode(newRoute)
    else
        local decoded = cjson.decode(routeObj)
        decoded[gatewayMethod] = {
            backendUrl    = backendUrl,
            backendMethod = backendMethod,
            policies      = policies
        }
        if security then
          decoded[gatewayMethod].security = security
        end
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
        ngx.status = 500
        ngx.say(utils.concatStrings({"Failed adding Route to redis: ", err}))
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
        ngx.status = 500
        ngx.say("Error getting route: ", err)
        ngx.exit(ngx.status)
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
        ngx.status = 500
        ngx.say("Error deleting route: ", err)
        ngx.exit(ngx.status)
    end

    if routeObj == ngx.null then
        ngx.status = 404
        ngx.say("Route doesn't exist.")
        ngx.exit(ngx.status)
    end

    local ok, err = red:del(key)
    if not ok then
        ngx.status = 500
        ngx.say("Error deleing route: ", err)
        ngx.exit(ngx.status)
    end
end


--- Subscribe to redis
-- @param redisSubClient the redis client that is listening for the redis key changes
-- @param redisGetClient the redis client that gets the changed route to update the conf file
-- @param ngx
function _M.subscribe(redisSubClient, redisGetClient, ngx)
    local ok, err = redisSubClient:psubscribe("__keyspace@0__:routes:*:*")
    if not ok then
        ngx.status = 500
        ngx.say("Subscribe error: ", err)
        ngx.exit(ngx.status)
    end

    ngx.say("Subscribed to redis and listening for key changes...")
    ngx.flush(true)

    subscribe(redisSubClient, redisGetClient, ngx)
    ngx.exit(ngx.status)
end

--- Subscribe helper method
-- Starts a while loop that listens for key changes in redis
-- @param redisSubClient the redis client that is listening for the redis key changes
-- @param redisGetClient the redis client that gets the changed route to update the conf file
-- @param ngx
function subscribe(redisSubClient, redisGetClient, ngx)
    while true do
        local res, err = redisSubClient:read_reply()
        if not res then
            if err ~= "timeout" then
                ngx.say("Read reply error: ", err)
                ngx.exit(ngx.status)
            end
        else
            local index = 1
            local redisKey = ""
            local namespace = ""
            for word in string.gmatch(res[3], '([^:]+)') do
                if index == 2 then
                    redisKey = utils.concatStrings({redisKey, word, ":"})
                elseif index == 3 then
                    namespace = word
                    redisKey = utils.concatStrings({redisKey, namespace, ":"})
                elseif index == 4 then
                    gatewayPath = word
                    redisKey = utils.concatStrings({redisKey, gatewayPath})
                end
                index = index + 1
            end

            local routeObj = _M.getRoute(redisGetClient, redisKey, "route", ngx)

            if routeObj == nil then
                filemgmt.deleteRouteConf(BASE_CONF_DIR, namespace, ngx.escape_uri(gatewayPath))
                ngx.say(utils.concatStrings({redisKey, " deleted"}))
                ngx.log(ngx.INFO, utils.concatStrings({redisKey, " deleted"}))
            else
                filemgmt.createRouteConf(BASE_CONF_DIR, namespace, ngx.escape_uri(gatewayPath), routeObj)
                ngx.say(utils.concatStrings({redisKey, " updated"}))
                ngx.log(ngx.INFO, utils.concatStrings({redisKey, " updated"}))
            end

            ngx.flush(true)
        end
    end
    ngx.exit(ngx.status)
end


--- Unsubscribe from redis
function _M.unsubscribe(red, ngx)
    local ok, err = red:unsubscribe("__keyspace@0__:routes:*:*")
    if not ok then
        ngx.status = 500
        ngx.say("Unsubscribe error: ", err)
        ngx.exit(ngx.status)
    end

    _M.close(red, ngx)

    ngx.say("Unsubscribed from redis")
    ngx.exit(ngx.status)
end

return _M
