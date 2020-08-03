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

local utils = require "lib/utils"
local request = require "lib/request"
local logger = require "lib/logger"

local _M = {}

--- Validate that the given subscription is in the datastore
-- @param dataStore the datastore object
-- @param tenant the namespace
-- @param gatewayPath the gateway path to use, if scope is resource
-- @param apiId api Id to use, if scope is api
-- @param scope scope of the subscription
-- @param apiKey the subscription api key
-- @param return boolean value indicating if the subscription exists in redis
local function validate(dataStore, tenant, gatewayPath, apiId, scope, apiKey)
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
  if dataStore:exists(k) == 1 then
    return k
  else
    return nil
  end
end

--- Process the security object
-- @param dataStore the datastore object
-- @param securityObj security object from nginx conf file
-- @param hashFunction a function that will be called to hash the string
-- @return apiKey api key for the subscription
local function processWithHashFunction(dataStore, securityObj, hashFunction)
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = dataStore:resourceToApi(utils.concatStrings({'resources:', tenant, ':', gatewayPath}))
  local scope = securityObj.scope
  local queryString = ngx.req.get_uri_args()
  local location = (securityObj.location == nil) and 'header' or securityObj.location
-- backwards compatible with "header" argument for name value. "name" argument takes precedent if both provided
  local name = (securityObj.name == nil and securityObj.header == nil) and 'x-api-key' or (securityObj.name or securityObj.header)
  local apiKey = nil

  ngx.log(ngx.DEBUG, "Processing API_KEY security policy")

  if location == "header" then
    apiKey = ngx.var[utils.concatStrings({'http_', name}):gsub("-", "_")]
  end
  if location == "query" then
    apiKey = queryString[name]
  end
  if apiKey == nil or apiKey == '' then
    request.err(401, 'Unauthorized')
    return nil
  end
  if securityObj.hashed then
    apiKey = hashFunction(apiKey)
  end
  local key = validate(dataStore, tenant, gatewayPath, apiId, scope, apiKey)
  if key == nil then
    request.err(401, 'Unauthorized')
    return nil
  end
  ngx.var.apiKey = apiKey
  return apiKey
end

local function process(dataStore, securityObj)
  return processWithHashFunction(dataStore, securityObj, utils.sha256)
end

_M.processWithHashFunction = processWithHashFunction
_M.process = process

return _M
