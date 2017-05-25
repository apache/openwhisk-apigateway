-- Copyright (c) 2016 IBM. All rights reserved.
--
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

--- @module clientSecret
-- Check a subscription with a client id and a hashed secret
local _M = {}

local dataStore = require "lib/dataStore"
local utils = require "lib/utils"
local request = require "lib/request"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

--- Process function main entry point for the security block.
--  Takes 2 headers and decides if the request should be allowed based on a hashed secret key
--@param securityObj the security object loaded from nginx.conf
--@return a string representation of what this looks like in redis :clientsecret:clientid:hashed secret
function process(dataStore, securityObj)
  local result = processWithHashFunction(dataStore, securityObj, utils.hash)
end

--- In order to properly test this functionallity, I use this function to do all of the business logic with injected dependencies
-- Takes 2 headers and decides if the request should be allowed based on a hashed secret key
-- @param red the redis instance to perform the lookup on
-- @param securityObj the security configuration for the tenant/resource/api we are verifying
-- @param hashFunction the function used to perform the hash of the api secret
function processWithHashFunction(dataStore, securityObj, hashFunction)
  -- pull the configuration from nginx
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = ngx.var.apiId
  local scope = securityObj.scope

  -- allow support for custom headers
  local location = (securityObj.keyLocation == nil) and 'http_' or securityObj.keyLocation
  if location == 'header' then
    location = 'http_'
  end

  local clientIdName = (securityObj.idFieldName == nil) and 'X-Client-ID' or securityObj.idFieldName

  local clientId = ngx.var[utils.concatStrings({location, clientIdName}):gsub("-", "_")]
  -- if they didn't supply whatever header this is configured to require, error out
  if clientId == nil or clientId == '' then
    request.err(401, clientIdName .. " required")
    return false
  end
  local clientSecretName = (securityObj.secretFieldName == nil) and 'X-Client-Secret' or securityObj.secretFieldName
  _G.clientSecretName = clientSecretName:lower()

  local clientSecret = ngx.var[utils.concatStrings({location, clientSecretName}):gsub("-","_")]
  if clientSecret == nil or clientSecret == '' then
    request.err(401, clientSecretName .. " required")
    return false
  end
-- hash the secret
  local result = validate(dataStore, tenant, gatewayPath, apiId, scope, clientId, hashFunction(clientSecret))
  if result == nil then
    request.err(401, "Secret mismatch or not subscribed to this api.")
  end
  ngx.var.apiKey = clientId
  return result
end

--- Validate that the subscription exists in redis
-- @param tenant the tenantId we are checking for
-- @param gatewayPath the possible resource we are checking for
-- @param apiId if we are checking for an api
-- @param scope which values should we be using to find the location of the secret
-- @param clientId the subscribed client id
-- @param clientSecret the hashed client secret
function validate(dataStore, tenant, gatewayPath, apiId, scope, clientId, clientSecret)
-- Open connection to redis or use one from connection pool
  local k
  if scope == 'tenant' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant})
  elseif scope == 'resource' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':resource:', gatewayPath})
  elseif scope == 'api' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':api:', apiId})
  end
  -- using the same key location in redis, just using :clientsecret: instead of :key:
  k = utils.concatStrings({k, ':clientsecret:', clientId, ':', clientSecret})
  if dataStore:exists(k) == 1 then
    return k
  else
    return nil
  end
end
_M.processWithHashFunction = processWithHashFunction
_M.process = process
return _M
