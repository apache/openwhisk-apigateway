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
local dataStore = require "lib/dataStore"
local cjson = require "cjson"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}



-- Process the security object
-- @param securityObj security object from nginx conf file
-- @return oauthId oauth identification
function process(ds, securityObj)
  local accessToken = ngx.var['http_Authorization']
  if accessToken == nil then
    request.err(401, "No Authorization header provided")
    return nil
  end
  accessToken = string.gsub(accessToken, '^Bearer%s', '')
 
  local token = exchange(ds, accessToken, securityObj.provider)
  if token == nil then
    request.err(401, 'Token didn\'t work or provider doesn\'t support OpenID connect. ')
    return nil
  end

  if token.error ~= nil then
    request.err(401, 'Token didn\'t work or provider doesn\'t support OpenID connect. ')
    return nil
  end

  return token
end

--- Exchange tokens with an oauth provider. Loads a provider based on configuration in the nginx.conf
-- @param token the accessToken passed in the authorization header of the routing request
-- @param provider the name of the provider we will load from a file. Currently supported google/github/facebook
-- @return the json object recieved from exchanging tokens with the provider
function exchange(ds, token, provider)
    -- exchange tokens with the provider
    local loaded, provider = pcall(require, utils.concatStrings({'oauth/', provider}))
 
    if not loaded then
      request.err(500, 'Error loading OAuth provider authentication module')
      print("error loading provider.")
      return nil
    end
    local token = provider(ds, token)
    -- cache the token
    return token
end

_M.process = process
return _M
