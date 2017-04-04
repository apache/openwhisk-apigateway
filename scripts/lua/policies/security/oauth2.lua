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

--- @module oauth
-- A module to check with an oauth provider and reject an api call with a bad oauth token
-- @author David Green (greend), Alex Song (songs)



local utils = require "lib/utils"
local request = require "lib/request"
local redis = require "lib/redis"
local cjson = require "cjson"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

-- Process the security object
-- @param securityObj security object from nginx conf file 
-- @return oauthId oauth identification
local _M = {}

function process(securityObj) 
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000) 
  local result = processWithRedis(red, securityObj)
  redis.close(red)
  return result
end

function processWithRedis(red, securityObj) 
  
  local accessToken = ngx.var['http_Authorization']
  if accessToken == nil then
    request.err(401, "No Authorization header provided")
  end
  accessToken = string.gsub(accessToken, '^Bearer%s', '')
  local token = {}
  local key = utils.concatStrings({"oauth:providers:", securityObj.provider, ":tokens:", accessToken})
  -- If we haven't cached the token go to the oauth provider
  if not (redis.exists(red, key) == 1) then
    token = exchange(accessToken, securityObj.provider)
  else 
    token = cjson.decode(redis.get(red, key))
  end

  if token == nil or not (token.error == nil) then
    request.err(401, "Token didn't work or provider doesn't support OpenID connect.") 
    return false
  end
  redis.set(red, key, cjson.encode(token))
  
  if not token.expires == nil then
    redis.expire(red, key, token.expires)
  end
  return key
-- only check with the provider if we haven't cached the token. 

end

--- Exchange tokens with an oauth provider. Loads a provider based on configuration in the nginx.conf
-- @param token the accessToken passed in the authorization header of the routing request
-- @param provider the name of the provider we will load from a file. Currently supported google/github/facebook
-- @return the json object recieved from exchanging tokens with the provider
  function exchange(token, provider) 
    -- exchange tokens with the provider
    local loaded, provider = pcall(require, utils.concatStrings({'oauth/', provider}))
   
    if not loaded then 
      request.err(500, 'Error loading OAuth provider authentication module')
      return 
    end
    local token = provider(token)
    -- cache the token
    return token
end

_M.process = process
_M.processWithRedis = processWithRedis
return _M
