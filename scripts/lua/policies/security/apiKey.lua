--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

--- @module apiKey
-- Check a subscription with an API Key
-- @author Cody Walker (cmwalker), Alex Song (songs)

local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"

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
-- @param apiKey the subscription api key
-- @param return boolean value indicating if the subscription exists in redis
function validate(red, tenant, gatewayPath, apiId, scope, apiKey)
  -- Open connection to redis or use one from connection pool
  local k
  if scope == 'tenant' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant})
  elseif scope == 'resource' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':resource:', gatewayPath})
  elseif scope == 'api' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':api:', apiId})
  end
  k = utils.concatStrings({k, ':key:', apiKey})
  if redis.exists(red, k) == 1 then
    return k
  else
    return nil
  end
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
  if apiKey == nil or apiKey == '' then
    request.err(401, 'Unauthorized')
    return nil
  end
  if securityObj.hashed then
    apiKey = hashFunction(apiKey)
  end
  local key = validate(red, tenant, gatewayPath, apiId, scope, apiKey)
  if key == nil then
    request.err(401, 'Unauthorized')
    return nil
  end
  ngx.var.apiKey = apiKey
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
  return resty_str.to_hex(digest)
end

_M.process = process
_M.processWithRedis = processWithRedis

return _M
