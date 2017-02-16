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

--- @module Cors
-- Used to add a Cors header when none is present 

local _M = {}
local utils = require "lib/utils" 
local redis = require "lib/redis" 
local cjson = require "cjson"
local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

function processCall(tenant, gatewayPath) 
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  
  local config = red:hget(utils.concatStrings({'resources:', tenant, ':', gatewayPath}), 'resources')
  local resourceConfig = cjson.decode(config)
  
  if resourceConfig.apiId == nil then
    return nil, nil
  end 

  local apiConfig = cjson.decode(red:hget('apis', resourceConfig.apiId))

  -- if they didn't set an apiId inside of their resource, we can't do this.. just silently error out
  if apiConfig.cors == nil then
    return nil, nil
  end 
  return apiConfig.cors.origin, apiConfig.cors.methods
end

_M.processCall = processCall

return _M
