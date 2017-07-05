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

--- @module resources
-- Management interface for resources for the gateway

local redis = require "lib/redis"
local utils = require "lib/utils"

local REDIS_FIELD = "resources"
local _M = {}

--- Helper function for adding a resource to redis and creating an nginx conf file
-- @param red
-- @param resource
-- @param gatewayPath
-- @param tenantObj
function _M.addResource(red, resource, gatewayPath, tenantObj)
  -- Create resource object and add to redis
  local redisKey = utils.concatStrings({"resources:", tenantObj.id, ":", gatewayPath})
  local operations = resource.operations
  local apiId = resource.apiId
  local cors = resource.cors
  local resourceObj = redis.generateResourceObj(operations, apiId, tenantObj, cors)
  redis.createResource(red, redisKey, REDIS_FIELD, resourceObj)
  local indexKey = utils.concatStrings({"resources:", tenantObj.id, ":__index__"})
  redis.addResourceToIndex(red, indexKey, redisKey)
end

--- Helper function for deleting resource in redis and appropriate conf files
-- @param red redis instance
-- @param gatewayPath path in gateway
-- @param tenantId tenant id
function _M.deleteResource(red, gatewayPath, tenantId)
  local redisKey = utils.concatStrings({"resources:", tenantId, ":", gatewayPath})
  redis.deleteResource(red, redisKey, REDIS_FIELD)
  local indexKey = utils.concatStrings({"resources:", tenantId, ":__index__"})
  redis.deleteResourceFromIndex(red, indexKey, redisKey)
end

return _M
