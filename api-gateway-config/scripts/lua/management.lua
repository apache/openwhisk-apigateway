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
-- Defines and exposes a lightweight API management to create and remove resources in the running API Gateway
-- @author Alex Song (songs)

local cjson = require "cjson"
local redis = require "lib/redis"
local filemgmt = require "lib/filemgmt"
local utils = require "lib/utils"
local logger = require "lib/logger"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local REDIS_FIELD = "resources"

local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local _M = {}

--- Add/update a resource to redis and create/update an nginx conf file given PUT JSON body
--
-- PUT http://0.0.0.0:9000/resources/<namespace>/<url-encoded-resource>
-- Example PUT JSON body:
-- {
--      "api": "12345"
--      "gatewayMethod": "GET",
--      "backendURL": "http://openwhisk.ng.bluemix.net/guest/action?blocking=true",
--      "backendMethod": "POST",
--      "policies": [],
--      "security": {
--        "type": "apikey"
--      }
--  }
--
function _M.addResource()
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

  -- Error handling for required fields in the request body
  local gatewayMethod = decoded.gatewayMethod
  if not gatewayMethod then
    ngx.status = 400
    ngx.say("Error: \"gatewayMethod\" missing from request body.")
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
  -- apiId, policies, security fields are optional
  local apiId = decoded.apiId
  local policies = decoded.policies
  local security = decoded.security

  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local namespace = list[2]
  local gatewayPath = list[3]
  local redisKey = utils.concatStrings({"resources", ":", namespace, ":", ngx.unescape_uri(gatewayPath)})

  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)

  local resourceObj = redis.generateResourceObj(red, redisKey, gatewayMethod, backendUrl, backendMethod, apiId, policies, security)
  redis.createResource(red, redisKey, REDIS_FIELD, resourceObj)
  filemgmt.createResourceConf(BASE_CONF_DIR, namespace, gatewayPath, resourceObj)

  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)

  ngx.status = 200
  ngx.header.content_type = "application/json; charset=utf-8"
  local managedUrlObj = {
    managedUrl = utils.concatStrings({"http://0.0.0.0/api/", namespace, "/", gatewayPath})
  }
  local managedUrlObj = cjson.encode(managedUrlObj)
  managedUrlObj = managedUrlObj:gsub("\\", "")
  ngx.say(managedUrlObj)
  ngx.exit(ngx.status)
end

--- Get resource from redis
--
-- GET http://0.0.0.0:9000/resources/<namespace>/<url-encoded-resource>
--
function _M.getResource()
  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local namespace = list[2]
  local gatewayPath = list[3]
  local redisKey = utils.concatStrings({list[1], ":", namespace, ":", ngx.unescape_uri(gatewayPath)})

  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)

  local resourceObj = redis.getResource(red, redisKey, REDIS_FIELD)
  if resourceObj == nil then
    ngx.status = 404
    ngx.say("Resource doesn't exist.")
    ngx.exit(ngx.status)
  end

  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)

  -- Get available operations for the given resource
  resourceObj = cjson.decode(resourceObj)
  local operations = {}
  for k in pairs(resourceObj.operations) do
    operations[#operations+1] = k
  end

  ngx.status = 200
  ngx.header.content_type = "application/json; charset=utf-8"
  local managedUrlObj = {
    managedUrl = utils.concatStrings({"http://0.0.0.0/api/", namespace, "/", gatewayPath}),
    availableOperations = operations
  }
  local managedUrlObj = cjson.encode(managedUrlObj)
  managedUrlObj = managedUrlObj:gsub("\\", "")
  ngx.say(managedUrlObj)
  ngx.exit(ngx.status)
end

--- Delete resource from redis
--
-- DELETE http://0.0.0.0:9000/resources/<namespace>/<url-encoded-resource>
--
function _M.deleteResource()
  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local namespace = list[2]
  local gatewayPath = list[3]
  local redisKey = utils.concatStrings({list[1], ":", namespace, ":", ngx.unescape_uri(gatewayPath)})

  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)

  -- Return if resource doesn't exist
  redis.deleteResource(red, redisKey, REDIS_FIELD)

  -- Delete conf file
  filemgmt.deleteResourceConf(BASE_CONF_DIR, namespace, gatewayPath)

  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)

  ngx.status = 200
  ngx.say("Resource deleted.")
  ngx.exit(ngx.status)
end

--- Subscribe to redis
--
-- GET http://0.0.0.0:9000/subscribe
--
function _M.subscribe()
  -- Initialize and connect to redis
  local redisSubClient = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 600000)
  local redisGetClient = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)

  logger.info(utils.concatStrings({"\nConnected to redis at ", REDIS_HOST, ":", REDIS_PORT}))
  redis.subscribe(redisSubClient, redisGetClient)

  ngx.exit(200)
end

--- Unsusbscribe to redis
--
-- GET http://0.0.0.0:9000/unsubscribe
--
function _M.unsubscribe()
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.unsubscribe(red)

  ngx.status = 200
  ngx.say("Unsubscribed to channel resources")
  ngx.exit(ngx.status)
end

--- Add an apikey/subscription to redis
-- PUT http://0.0.0.0:9000/subscriptions/<namespace>/<url-encoded-resource>/<key>
--  where list[1] = prefix, list[2] = namespace, list[3] = gatewayPath, list[4] = key
------ or
-- PUT http://0.0.0.0:9000/subscriptions/<namespace>/<key>
-- where list[1] = prefix, list[2] = namespace, list[3] = key
function _M.addSubscription()
  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local redisKey
  if list[4] then
    redisKey = utils.concatStrings({list[1], ":", list[2], ":", ngx.unescape_uri(list[3]), ":", list[4]})
  else
    redisKey = utils.concatStrings({list[1], ":", list[2], ":", list[3]})
  end

  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)

  redis.createSubscription(red, redisKey)

  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)

  ngx.status = 200
  ngx.say("Subscription created.")
  ngx.exit(ngx.status)
end

--- Delete apikey/subscription from redis
-- DELETE http://0.0.0.0:9000/subscriptions/<namespace>/<url-encoded-resource>/<key>
--  where list[1] = prefix, list[2] = namespace, list[3] = gatewayPath, list[4] = key
------ or
-- DELETE http://0.0.0.0:9000/subscriptions/<namespace>/<key>
-- where list[1] = prefix, list[2] = namespace, list[3] = key
function _M.deleteSubscription()
  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local redisKey
  if list[4] then
    redisKey = utils.concatStrings({list[1], ":", list[2], ":", ngx.unescape_uri(list[3]), ":", list[4]})
  else
    redisKey = utils.concatStrings({list[1], ":", list[2], ":", list[3]})
  end

  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)

  -- Return if subscription doesn't exist
  redis.deleteSubscription(red, redisKey)

  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)

  ngx.status = 200
  ngx.say("Subscription deleted.")
  ngx.exit(ngx.status)
end


--- Parse the request uri to get the redisKey, namespace, and gatewayPath
-- @param requestURI
-- @return redisKey, namespace, gatewayPath
function parseRequestURI(requestURI)
  local list = {}
  for i in string.gmatch(requestURI, '([^/]+)') do
    list[#list + 1] = i
  end
  if not list[1] or not list[2] then
    ngx.status = 400
    ngx.say("Error: Request path should be \"/resources/<namespace>/<url-encoded-resource>\"")
    ngx.exit(ngx.status)
  end


  return list  --prefix, namespace, gatewayPath, apiKey
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
