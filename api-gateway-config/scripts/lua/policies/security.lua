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

function validateAPIKey(namespace ,apiKey)
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000, ngx)

  local k = utils.concatStrings({'subscriptions:', tostring(namespace), ':', tostring(apiKey)})
  local exists, err = red:exists(k)
  logger.debug(utils.concatStrings({'Got exists back from redis for key ', k, ': ', tostring(exists)}))

  return exists == 1
end

function processAPIKey()
  local namespace = ngx.var.namespace
  local apiKey = ngx.var['http_x_api_key']
  logger.debug(utils.concatStrings({'Processing apikey: ', apiKey, 'for namespace: ', namespace}))
  if not apiKey then
    logger.err('No x-api-key passed. Sending 401')
    ngx.exit(401)
  end
  local ok = validateAPIKey(namespace, apiKey)
  if not ok then
    logger.err('x-api-key does not match. Sending 401')
    ngx.exit(401)
  end
end

_M.processAPIKey = processAPIKey

return _M