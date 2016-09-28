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

--- @module management
-- Defines and exposes a lightweight API management to create and remove routes in the running API Gateway
-- @author Alex Song (songs)

local cjson = require "cjson"
local redis = require "lib/redis"
local filemgmt = require "lib/filemgmt" 
local utils = require "lib/utils"
local logger = require "lib/logger"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local subscribed = false

local _M = {}

--- Add/update a route to redis and create/update an nginx conf file given PUT JSON body
-- 
-- PUT http://0.0.0.0:9000/routes/<namespace>/<url-encoded-route>
-- Example PUT JSON body:
-- { 
--      "gatewayMethod": "GET", 
--      "backendURL": "http://openwhisk.ng.bluemix.net/guest/action?blocking=true", 
--      "backendMethod": "POST", 
--      "policies": [],
--      "security": {
--        "type": "apikey"
--      }
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
    local security = decoded.security
    local backendUrl = decoded.backendURL
    if not backendUrl then
        ngx.status = 400
        ngx.say("Error: \"backendURL\" missing from request body.")
        ngx.exit(ngx.status)
    end
    logger.debug(backendURL);
    -- Use gatewayMethod by default or usebackendMethod if specified
    local backendMethod = decoded and decoded.backendMethod or gatewayMethod

    local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
    local redisKey, namespace, gatewayPath = parseRequestURI(requestURI)
    
    -- Open connection to redis or use one from connection pool
    local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000, ngx)
    
    local routeObj = redis.generateRouteObj(red, redisKey, gatewayMethod, backendUrl, backendMethod, policies, security, ngx)
    redis.createRoute(red, redisKey, "route", routeObj, ngx)
    filemgmt.createRouteConf(BASE_CONF_DIR, namespace, gatewayPath, routeObj)

    -- Add current redis connection in the ngx_lua cosocket connection pool
    redis.close(red, ngx)

    ngx.status = 200
    local managedUrlObj = {
        managedUrl = utils.concatStrings({"http://0.0.0.0/api/", namespace, "/", gatewayPath})
    }
    ngx.say(cjson.encode(managedUrlObj))
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
    local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000, ngx)
    
    local routeObj = redis.getRoute(red, redisKey, "route", ngx)
    if routeObj == nil then
        ngx.status = 404
        ngx.say("Route doesn't exist.")
        ngx.exit(ngx.status)
    end

    -- Add current redis connection in the ngx_lua cosocket connection pool
    redis.close(red, ngx)

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
    local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000, ngx)

    -- Return if route doesn't exist
    redis.deleteRoute(red, redisKey, "route", ngx)
    
    -- Delete conf file
    filemgmt.deleteRouteConf(BASE_CONF_DIR, namespace, gatewayPath)
    
    -- Add current redis connection in the ngx_lua cosocket connection pool
    redis.close(red, ngx)

    ngx.status = 200
    ngx.say("Route deleted.")
    ngx.exit(ngx.status) 
end

--- Subscribe to redis
-- 
-- GET http://0.0.0.0:9000/subscribe
--
function _M.subscribe()
    -- Initialize and connect to redis
    logger.debug(utils.concatStrings({'Subscribing to Redis with host: ' , REDIS_HOST, '; port: ', REDIS_PORT, '; pass:', REDIS_PASS}))
    local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 60000, ngx)
    redis.subscribe(red, ngx)
    ngx.exit(200)
end

--- Unsusbscribe to redis
--
-- GET http://0.0.0.0:9000/unsubscribe
--
function _M.unsubscribe()
    -- Initialize and connect to redis
    logger.debug(utils.concatStrings({'Unsubscribing to Redis with host: ' , REDIS_HOST, '; port: ', REDIS_PORT, '; pass:', REDIS_PASS}))
    local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000, ngx)
    redis.unsubscribe(red, ngx)

    ngx.status = 200
    ngx.say("Unsubscribed to channel routes")
    ngx.exit(ngx.status)
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

    local redisKey = utils.concatStrings({prefix, ":", namespace, ":", ngx.unescape_uri(gatewayPath)})
    return redisKey, namespace, gatewayPath
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
            table.insert(jsonStringList, utils.concatStrings({"=", value}))
        end
    end
    return cjson.decode(utils.concatStrings(jsonStringList))
end



return _M
