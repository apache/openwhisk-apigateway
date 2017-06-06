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
  if redis.subscriptionExists(red, key) == 1 then
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
