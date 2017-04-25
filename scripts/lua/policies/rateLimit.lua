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

--- @module rateLimit

local utils = require "lib/utils"
local request = require "lib/request"

local _M = {}

--- Limit a resource/api/tenant, based on the passed in rateLimit object
-- @param red redis client instance
-- @param obj rateLimit object containing interval, rate, scope, subscription fields
-- @param apiKey optional api key to use if subscription is set to true
function limit(red, obj, apiKey)
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
  if red:get(k) == ngx.null then
    red:set(k, "", "PX", math.floor(rate*1000))
  else
    return request.err(429, 'Rate limit exceeded')
  end
end

_M.limit = limit

return _M
