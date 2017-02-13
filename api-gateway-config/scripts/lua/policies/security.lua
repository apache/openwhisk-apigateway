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

--- @module security
-- A module to load all and execute the security policies
-- @author David Green (greend), Alex Song (songs)

local _M = {}

local utils = require "lib/utils"
--- Allow or block a request by calling a loaded security policy
-- @param securityObj an object out of the security array in a given tenant / api / resource
function process(securityObj)
  local ok, result = pcall(require, utils.concatStrings({'policies/security/', securityObj.type}))
  if not ok then
    ngx.err(500, 'An unexpected error ocurred while processing the security policy') 
  end 
  
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = ngx.var.apiId
  local scope = securityObj.scope
  local apiKey = ngx.var[utils.concatStrings({'http_', header}):gsub("-", "_")]
 
  result.process(red, tenant, gatewayPath, apiId, scope, apiKey, securityObj)
end

-- Wrap process in code to load the correct module 
_M.process = process

return _M 
