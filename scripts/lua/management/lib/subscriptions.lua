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
