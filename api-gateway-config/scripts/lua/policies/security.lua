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

--- @module mapping
-- Process mapping object, turning implementation details into request transformations
-- @author Cody Walker (cmwalker)

local redis = require "lib/redis"
local utils = require "lib/utils"
local logger = require "lib/logger"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

function validateAPIKey(namespace, gatewayPath, apiKey)
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)

  local k = utils.concatStrings({'subscriptions:', tostring(namespace), ':', tostring(gatewayPath), ':', tostring(apiKey)})
  local exists, err = red:exists(k)
  if exists == 0 then
    k = utils.concatStrings({'subscriptions:', tostring(namespace), ':', tostring(apiKey)})
    exists, err = red:exists(k)
    end
  return exists == 1
end

function processAPIKey(h)
  local namespace = ngx.var.namespace
  local gatewayPath = ngx.var.gatewayPath
  local apiKey = ngx.var[h]
  if not apiKey then
    logger.err('No api-key passed. Sending 401')
    ngx.status = 401
    ngx.say('API key is required.')
    ngx.exit(ngx.status)
  end
  local ok = validateAPIKey(namespace, gatewayPath, apiKey)
  if not ok then
    logger.err('api-key does not match. Sending 401')
    ngx.status = 401
    ngx.say('Invalid API Key.')
    ngx.exit(ngx.status)
  end
end

_M.processAPIKey = processAPIKey

return _M
