--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

--- @module oauth
-- A module to check with an oauth provider and reject an api call with a bad oauth token

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
function process(dataStore, securityObj)
  local accessToken = ngx.var['http_Authorization']
  if accessToken == nil then
    request.err(401, "No Authorization header provided")
    return nil
  end

  accessToken = string.gsub(accessToken, '^[B|b][E|e][A|a][R|r][E|e][R|r]%s', '')

  local token = exchange(dataStore, accessToken, securityObj.provider, securityObj)
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
-- @param dataStore the datastore object
-- @param token the accessToken passed in the authorization header of the routing request
-- @param provider the name of the provider we will load from a file. Currently supported google/github/facebook
-- @return the json object recieved from exchanging tokens with the provider
function exchange(dataStore, token, provider, securityObj)
    -- exchange tokens with the provider
    local loaded, impl = pcall(require, utils.concatStrings({'oauth/', provider}))
    if not loaded then
      request.err(500, 'Error loading OAuth provider authentication module')
      print("error loading provider:", impl)
      return nil
    end

    local result = impl.process(dataStore, token, securityObj)
    if result == nil then
      request.err('401', 'OAuth token didn\'t work or provider doesn\'t support OpenID connect')
    end
    -- cache the token
    return result
end

_M.process = process
return _M
