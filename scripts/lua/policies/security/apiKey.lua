
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

--- @module apiKey
-- Check a subscription with an API Key
-- @author Cody Walker (cmwalker), Alex Song (songs)

local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"
local basexx = require "lib/basexx"
local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

--- Validate that the given subscription is in redis
-- @param red a redis instance to query against 
-- @param tenant the namespace
-- @param gatewayPath the gateway path to use, if scope is resource
-- @param apiId api Id to use, if scope is api
-- @param scope scope of the subscription
-- @param header the name of the header we are checking for 
-- @param apiKey the subscription api key
-- @param return boolean value indicating if the subscription exists in redis
function validate(red, tenant, gatewayPath, apiId, scope, header, apiKey)
  -- Open connection to redis or use one from connection pool
  local k
  if scope == 'tenant' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant})
  elseif scope == 'resource' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':resource:', gatewayPath})
  elseif scope == 'api' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':api:', apiId})
  end
  k = utils.concatStrings({k, ':key:', header, ':', apiKey})
  return red:exists(k) == 1
end

function process(securityObj) 
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local result = processWithRedis(red, securityObj, sha256)
  redis.close(red)
  return result
end 

--- Process the security object
-- @param red a redis instance to query against
-- @param securityObj security object from nginx conf file
-- @param hashFunction a function that will be called to hash the string
-- @return apiKey api key for the subscription
function processWithRedis(red, securityObj, hashFunction)
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = redis.resourceToApi(red, utils.concatStrings({'resources:', tenant, ':', gatewayPath})) 
  local scope = securityObj.scope
  local header = (securityObj.header == nil) and 'x-api-key' or securityObj.header
  local apiKey = ngx.var[utils.concatStrings({'http_', header}):gsub("-", "_")]
  if not apiKey then
    request.err(401, utils.concatStrings({'API key header "', header, '" is required.'}))
    return nil
  end
  if securityObj.hashed then
    apiKey = hashFunction(apiKey)
  end 
  local ok = validate(red, tenant, gatewayPath, apiId, scope, header, apiKey)
  if not ok then
    request.err(401, 'Invalid API key.')
    return nil
  end
  return apiKey
end

--- Calculate the sha256 hash of a string 
-- @param str the string you want to hash
-- @return a hashed version of the string
function sha256(str) 
  local resty_sha256 = require "resty.sha256" 
  local resty_str = require "resty.string" 
  local sha = resty_sha256:new() 
  sha:update(str) 
  local digest = sha:final()
  local raw = basexx.from_hex(resty_str.to_hex(digest)) 
  return basexx.to_base64(raw)
end 

_M.process = process
_M.processWithRedis = processWithRedis

return _M
