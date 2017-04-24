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
local subscriptions = require "management/lib/subscriptions"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

function _M.requestHandler()
  local version = ngx.var.version
  if version == "v2" then
    v2()
  elseif version == "v1" then
    v1()
  else
    request.err(404, "404 Not found")
  end
end


-- v2 -- 

function v2()
  local requestMethod = ngx.req.get_method()
  if requestMethod == "POST" or requestMethod == "PUT" then
    v2AddSubscription()
  elseif requestMethod == "GET" then
    v2GetSubscriptions()
  elseif requestMethod == "DELETE" then
    v2DeleteSubscription()
  else
    request.err(400, "Invalid verb")
  end
end

function v2AddSubscription()
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    request.err(400, "Missing request body.")
  end
  local decoded = cjson.decode(args)
  local res, err = utils.tableContainsAll(decoded, {"client_id", "artifact_id"})
  if res == false then
    request.err(err.statusCode, err.message)
  end
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local artifactId = decoded.artifact_id
  local tenantId = ngx.var.tenant_id
  local clientId = decoded.client_id
  local clientSecret = decoded.client_secret
  subscriptions.addSubscription(red, artifactId, tenantId, clientId, clientSecret, utils.hash)
  redis.close(red)
  local result = {
    message = utils.concatStrings({"Subscription '", clientId, "' created for API '", artifactId, "'"})
  }
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, cjson.encode(result))
end

function v2GetSubscriptions()
  local tenantId = ngx.var.tenant_id
  local artifactId = ngx.req.get_uri_args()["artifact_id"]
  if artifactId == nil or artifactId == "" then
    request.err(400, "Missing artifact_id")
  end
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local subscriptionList = subscriptions.getSubscriptions(red, artifactId, tenantId)
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, cjson.encode(subscriptionList))
end

function v2DeleteSubscription()
  local clientId = ngx.var.client_id
  local tenantId = ngx.var.tenant_id
  local artifactId = ngx.req.get_uri_args()["artifact_id"]
  if clientId == nil or clientId == "" then
    request.err(400, "Missing client_id")
  end
  if artifactId == nil or artifactId == "" then
    request.err(400, "Missing artifact_id")
  end
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local res = subscriptions.deleteSubscription(red, artifactId, tenantId, clientId)
  if res == false then
    request.err(404, "Subscription doesn't exist")
  end
  redis.close(red)
  request.success(204)
end


-- v1 --

function v1()
  local requestMethod = ngx.req.get_method()
  if requestMethod == "POST" or requestMethod == "PUT" then
    addSubscription()
  elseif requestMethod == "DELETE" then
    deleteSubscription()
  else
    request.err(400, "Invalid verb")
  end
end

function addSubscription()
  local redisKey = validateSubscriptionBody()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  redis.createSubscription(red, redisKey)
  redis.close(red)
  request.success(200, "Subscription created.")
end

function deleteSubscription()
  local redisKey = validateSubscriptionBody()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  redis.deleteSubscription(red, redisKey)
  redis.close(red)
  request.success(200, "Subscription deleted.")
end

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