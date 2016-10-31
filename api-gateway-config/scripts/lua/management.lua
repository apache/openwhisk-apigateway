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
local request = require "lib/request"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local REDIS_FIELD = "resources"

local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local _M = {}

--- Add/update a resource to redis and create/update an nginx conf file given PUT JSON body
-- PUT http://0.0.0.0:9000/resources/<tenant>/<url-encoded-resource>
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
function _M.addResource()
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_post_args()
  if not args then
    request.err(400, "Missing Request body")
  end
  -- Convert json into Lua table
  local decoded = utils.convertJSONBody(args)
  -- Error handling for required fields in the request body
  local gatewayMethod = decoded.gatewayMethod
  if not gatewayMethod then
    request.err(400, "\"gatewayMethod\" missing from request body.")
  end
  local backendUrl = decoded.backendURL
  if not backendUrl then
    request.err(400, "\"backendURL\" missing from request body.")
  end
  -- Use gatewayMethod by default or usebackendMethod if specified
  local backendMethod = decoded and decoded.backendMethod or gatewayMethod
  -- apiId, policies, security fields are optional
  local apiId = decoded.apiId
  -- TODO: Error handling needed for policies and security
  local policies = decoded.policies
  local security = decoded.security
  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local tenant = list[2]
  local gatewayPath = list[3]
  local redisKey = utils.concatStrings({"resources", ":", tenant, ":", ngx.unescape_uri(gatewayPath)})
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local resourceObj = redis.generateResourceObj(red, redisKey, gatewayMethod, backendUrl, backendMethod, apiId, policies, security)
  redis.createResource(red, redisKey, REDIS_FIELD, resourceObj)
  filemgmt.createResourceConf(BASE_CONF_DIR, tenant, gatewayPath, resourceObj)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  -- Return managed url object
  local managedUrlObj = {
    managedUrl = utils.concatStrings({"http://0.0.0.0/api/", tenant, "/", gatewayPath})
  }
  managedUrlObj = cjson.encode(managedUrlObj):gsub("\\", "")
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, managedUrlObj)
end

--- Get resource from redis
-- GET http://0.0.0.0:9000/resources/<tenant>/<url-encoded-resource>
function _M.getResource()
  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local tenant = list[2]
  local gatewayPath = list[3]
  local redisKey = utils.concatStrings({list[1], ":", tenant, ":", ngx.unescape_uri(gatewayPath)})
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local resourceObj = redis.getResource(red, redisKey, REDIS_FIELD)
  if resourceObj == nil then
    request.err(404, "Resource doesn't exist.")
  end
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  -- Get available operations for the given resource
  resourceObj = cjson.decode(resourceObj)
  local operations = {}
  for k in pairs(resourceObj.operations) do
    operations[#operations+1] = k
  end
  -- Return managed url object
  local managedUrlObj = {
    managedUrl = utils.concatStrings({"http://0.0.0.0/api/", tenant, "/", gatewayPath}),
    availableOperations = operations
  }
  managedUrlObj = cjson.encode(managedUrlObj):gsub("\\", "")
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, managedUrlObj)
end

--- Delete resource from redis
-- DELETE http://0.0.0.0:9000/resources/<tenant>/<url-encoded-resource>
function _M.deleteResource()
  local requestURI = string.gsub(ngx.var.request_uri, "?.*", "")
  local list = parseRequestURI(requestURI)
  local tenant = list[2]
  local gatewayPath = list[3]
  local redisKey = utils.concatStrings({list[1], ":", tenant, ":", ngx.unescape_uri(gatewayPath)})
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  -- Return if resource doesn't exist
  redis.deleteResource(red, redisKey, REDIS_FIELD)
  -- Delete conf file
  filemgmt.deleteResourceConf(BASE_CONF_DIR, tenant, gatewayPath)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  request.success(200, "Resource deleted.")
end

--- Subscribe to redis
-- GET http://0.0.0.0:9000/subscribe
function _M.subscribe()
  -- Initialize and connect to redis
  local redisGetClient = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local redisSubClient = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 60000) -- read_reply will timeout every minute
  logger.info(utils.concatStrings({"\nConnected to redis at ", REDIS_HOST, ":", REDIS_PORT}))
  redis.subscribe(redisSubClient, redisGetClient)
  ngx.exit(200)
end

--- Unsusbscribe to redis
-- GET http://0.0.0.0:9000/unsubscribe
function _M.unsubscribe()
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.unsubscribe(red)
  request.success(200, "Unsubscribed to redis")
end

--- Add an apikey/subscription to redis
-- PUT http://0.0.0.0:9000/subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenant: *(String) tenant id
--    resource: (String) url-encoded resource path
--    api: (String) api id
-- }
function _M.addSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.createSubscription(red, redisKey)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  request.success(200, "Subscription created.")
end

--- Delete apikey/subscription from redis
-- DELETE http://0.0.0.0:9000/subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenant: *(String) tenant id
--    resource: (String) url-encoded resource path
--    api: (String) api id
-- }
function _M.deleteSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  -- Return if subscription doesn't exist
  redis.deleteSubscription(red, redisKey)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  request.success(200, "Subscription deleted.")
end

--- Check the request JSON body for correct fields
-- @return redisKey subscription key for redis
function validateSubscriptionBody()
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_post_args()
  if not args then
    request.err(400, "Missing request body.")
  end
  -- Convert json into Lua table
  local decoded
  if next(args) then
    decoded = utils.convertJSONBody(args)
  else
    request.err(400, "Request body required.")
  end
  -- Check required fields
  local requiredFieldList = {"key", "scope", "tenant"}
  for i, field in ipairs(requiredFieldList) do
    if not decoded[field] then
      request.err(400, utils.concatStrings({"\"", field, "\" missing from request body."}))
    end
  end
  -- Check if we're using tenant or resource or api
  local resource = decoded.resource
  local apiId = decoded.apiId
  local redisKey
  local prefix = utils.concatStrings({"subscriptions:tenant:", decoded.tenant})
  if decoded.scope == "tenant" then
    redisKey = prefix
  elseif decoded.scope == "resource" then
    if resource ~= nil then
      redisKey = utils.concatStrings({prefix, ":resource:", resource})
    else
      request.err(400, "\"resource\" missing from request body.")
    end
  elseif decoded.scope == "api" then
    if apiId ~= nil then
      redisKey = utils.concatStrings({prefix, ":api:", apiId})
    else
      request.err(400, "\"apiId\" missing from request body.")
    end
  else 
    request.err(400, "Invalid scope")
  end
  redisKey = utils.concatStrings({redisKey, ":key:", decoded.key})
  return redisKey
end

--- Parse the request uri to get the redisKey, tenant, and gatewayPath
-- @param requestURI String containing the uri in the form of "/resources/<tenant>/<path>"
-- @return list containing redisKey, tenant, gatewayPath
function parseRequestURI(requestURI)
  local list = {}
  for i in string.gmatch(requestURI, '([^/]+)') do
    list[#list + 1] = i
  end
  if not list[1] or not list[2] then
    request.err(400, "Request path should be \"/resources/<tenant>/<url-encoded-resource>\"")
  end

  return list  --prefix, tenant, gatewayPath, apiKey
end

return _M