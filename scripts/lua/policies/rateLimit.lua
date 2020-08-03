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

--- @module rateLimit

local utils = require "lib/utils"
local request = require "lib/request"

local _M = {}

--- Limit a resource/api/tenant, based on the passed in rateLimit object
-- @param dataStore the datastore object
-- @param obj rateLimit object containing interval, rate, scope, subscription fields
-- @param apiKey optional api key to use if subscription is set to true
local function limit(dataStore, obj, apiKey)
  local rate = obj.interval / obj.rate
  local tenantId = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local k
  -- Check scope
  if obj.scope == "tenant" then
    k = utils.concatStrings({"ratelimit:tenant:", tenantId})
  elseif obj.scope == "api" then
    local apiId = ngx.var.apiId
    k = utils.concatStrings({"ratelimit:tenant:", tenantId, ":api:", apiId})
  elseif obj.scope == "resource" then
    k = utils.concatStrings({"ratelimit:tenant:", tenantId, ":resource:", gatewayPath})
  end
  -- Check subscription
  if obj.subscription ~= nil and obj.subscription == true and apiKey ~= nil then
    k = utils.concatStrings({k, ":subscription:", apiKey})
  end

  if dataStore:getRateLimit(k) == ngx.null then
    dataStore:setRateLimit(k, "", "PX", math.floor(rate*1000))
  else
    return request.err(429, 'Rate limit exceeded')
  end
end

_M.limit = limit

return _M
