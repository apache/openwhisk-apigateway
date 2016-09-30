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
-- Process a rateLimit object, setting the rate and interval to the request
-- @author David Green (greend)

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")
local request = require "lib/resty/limit/req"
local utils = require "lib/utils"
local logger = require "lib/logger"

local _M = {}

function limit(obj)
  local i = 60 / obj.interval
  local r = i * obj.rate
  r = utils.concatStrings({tostring(r), 'r/m'})
  logger.debug(utils.concatStrings({'Limiting using rate: ', r}))
  logger.debug(utils.concatStrings({'Limiting using interval: ', obj.interval}))
  logger.debug(utils.concatStrings({'Limiting using redis config host: ' , REDIS_HOST, '; port: ', REDIS_PORT, '; pass:', REDIS_PASS}))
  local k
   if obj.field == 'namespace' then
     k = ngx.var.namespace
   elseif obj.field == 'apikey' then
     k = utils.concatStrings({ngx.var.namespace, '_', ngx.var['http_x_api_key']})
   elseif obj.field == 'route' then
     k = utils.concatStrings({ngx.var.namespace, '_', ngx.var.gatewayPath})
   end

  local config = {
     key = k,
     zone = 'rateLimiting',
     rate = r,
     interval = obj.interval,
     log_level = ngx.NOTICE,
     rds = { host = REDIS_HOST, port = REDIS_PORT }
   }
  local ok = request.limit (config)
  if not ok then
    logger.err('Rate limit exceeded. Sending 429')
    ngx.exit(429)
  end
end

_M.limit = limit

return _M