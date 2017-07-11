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

--- @module subscriptions
-- Management interface for subscriptions for the gateway

local redis = require "lib/redis"
local utils = require "lib/utils"

local _M = {}

function _M.addSubscription(dataStore, artifactId, tenantId, clientId, clientSecret, hashFunction)
  local subscriptionKey = utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId})
  dataStore:setSnapshotId(tenantId)
  if clientSecret ~= nil then
    if hashFunction == nil then
      hashFunction = utils.hash
    end
    subscriptionKey = utils.concatStrings({subscriptionKey, ":clientsecret:", clientId, ":", hashFunction(clientSecret)})
  else
    subscriptionKey = utils.concatStrings({subscriptionKey, ":key:", clientId})
  end
  dataStore:createSubscription(subscriptionKey)
end

function _M.getSubscriptions(dataStore, artifactId, tenantId)
  dataStore:setSnapshotId(tenantId)
  return dataStore:getSubscriptions(artifactId, tenantId)
end

function _M.deleteSubscription(dataStore, artifactId, tenantId, clientId)
  return dataStore:deleteSubscriptionAdv(artifactId, tenantId, clientId)
end

return _M
