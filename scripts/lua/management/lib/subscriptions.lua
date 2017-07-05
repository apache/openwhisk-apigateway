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

function _M.addSubscription(red, artifactId, tenantId, clientId, clientSecret, hashFunction)
  local subscriptionKey = utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId})
  if clientSecret ~= nil then
    if hashFunction == nil then
      hashFunction = utils.hash
    end
    subscriptionKey = utils.concatStrings({subscriptionKey, ":clientsecret:", clientId, ":", hashFunction(clientSecret)})
  else
    subscriptionKey = utils.concatStrings({subscriptionKey, ":key:", clientId})
  end
  redis.createSubscription(red, subscriptionKey)
end

function _M.getSubscriptions(red, artifactId, tenantId)
  local res = red:scan(0, "match", utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId, ":*"}))
  local cursor = res[1]
  local subscriptions = {}
  for _, v in pairs(res[2]) do
    local matched = {string.match(v, "subscriptions:tenant:([^:]+):api:([^:]+):([^:]+):([^:]+):*")}
    subscriptions[#subscriptions + 1] = matched[4]
  end
  while cursor ~= "0" do
    res = red:scan(cursor, "match", utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId, ":*"}))
    cursor = res[1]
    for _, v in pairs(res[2]) do
      local matched = {string.match(v, "subscriptions:tenant:([^:]+):api:([^:]+):([^:]+):([^:]+):*")}
      subscriptions[#subscriptions + 1] = matched[4]
    end
  end
  return subscriptions
end

function _M.deleteSubscription(red, artifactId, tenantId, clientId)
  local subscriptionKey = utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId})
  local key = utils.concatStrings({subscriptionKey, ":key:", clientId})
  if redis.exists(red, key) == 1 then
    redis.deleteSubscription(red, key)
  else
    local pattern = utils.concatStrings({subscriptionKey, ":clientsecret:" , clientId, ":*"})
    local res = red:eval("return redis.call('del', unpack(redis.call('keys', ARGV[1])))", 0, pattern)
    if res == false then
      return false
    end
  end
  return true
end

return _M