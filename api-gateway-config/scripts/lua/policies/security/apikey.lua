
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

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

--- Validate that the given subscription is in redis
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
  local exists = red:exists(k)
  redis.close(red)
  return exists == 1
end

--- Process the security object
-- @param securityObj security object from nginx conf file
-- @return apiKey api key for the subscription
function process(red, tenant, gatewayPath, apiId, scope, apiKey, securityObj)
  local header = (securityObj.header == nil) and 'x-api-key' or securityObj.header
  if not apiKey then
    request.err(401, utils.concatStrings({'API key header "', header, '" is required.'}))
  end
  local ok = validate(red, tenant, gatewayPath, apiId, scope, apiKey)
  if not ok then
    request.err(401, 'Invalid API key.')
  end
  return apiKey
end

_M.process = process
return _M
