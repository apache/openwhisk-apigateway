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

--- @module subscriptions
-- Management interface for subscriptions for the gateway

local cjson = require "cjson"
local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

--- Request handler for routing API calls appropriately
function _M.requestHandler()
  local requestMethod = ngx.req.get_method()
  if requestMethod == "PUT" then
    addSubscription()
  elseif requestMethod == "DELETE" then
    deleteSubscription()
  else
    ngx.status = 400
    ngx.say("Invalid verb")
  end
end

--- Add an apikey/subscription to redis
-- PUT /v1/subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenantId: *(String) tenant id
--    resource: (String) url-encoded resource path
--    apiId: (String) api id
-- }
function addSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  redis.createSubscription(red, redisKey)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  request.success(200, "Subscription created.")
end

--- Delete apikey/subscription from redis
-- DELETE /v1/subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenantId: *(String) tenant id
--    resource: (String) url-encoded resource path
--    apiId: (String) api id
-- }
function deleteSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
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
  local args = ngx.req.get_body_data()
  if not args then
    request.err(400, "Missing request body.")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Check required fields
  local res, err = utils.tableContainsAll(decoded, {"key", "scope", "tenantId"})
  if res == false then
    request.err(err.statusCode, err.message)
  end
  -- Check if we're using tenant or resource or api
  local resource = decoded.resource
  local apiId = decoded.apiId
  local redisKey
  local prefix = utils.concatStrings({"subscriptions:tenant:", decoded.tenantId})
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

return _M