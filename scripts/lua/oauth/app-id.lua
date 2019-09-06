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
local request = require 'lib/request'
local cjson = require 'cjson'
local utils = require 'lib/utils'
local APPID_PKURL = os.getenv("APPID_PKURL")
local _M = {}
local http = require 'resty.http'
local cjose = require 'resty.cjose'

local function inject_req_headers(token_obj)
  ngx.header['X-OIDC-Email'] = token_obj['email']
  ngx.header['X-OIDC-Sub'] = token_obj['sub']
end

local function fetchJWKs(tenantId)
  local httpc = http.new()
  local keyUrl = utils.concatStrings({APPID_PKURL, tenantId, '/publickeys'})
  local request_options = {
    headers = {
      ["Accept"] = "application/json"
    },
    ssl_verify = true
  }
  return httpc:request_uri(keyUrl, request_options)
end

function _M.process(dataStore, token, securityObj)
  local cache_key = 'appid_' .. securityObj.tenantId
  local result = dataStore:getOAuthToken(cache_key, token)
  local token_obj

  -- Was the token in the cache?
  if result ~= ngx.null then
    token_obj = cjson.decode(result)
    inject_req_headers(token_obj)
    return token_obj
  end

  -- Cache miss. Proceed to validate the token
  local res, err = fetchJWKs(securityObj.tenantId)
  if err ~= nil or not res or res.status ~= 200 then
    request.err(500, 'An error occurred while fetching the App ID JWK configuration: ' .. err or res.body)
    return nil
  end

  local key
  local keys = cjson.decode(res.body).keys
  for _, v in ipairs(keys) do
    key = v
  end
  local result = cjose.validateJWS(token, cjson.encode(key))
  if not result then
    request.err(401, 'The token signature did not match any known JWK.')
    return nil
  end

  token_obj = cjson.decode(cjose.getJWSInfo(token))
  local expireTime = token_obj['exp']
  if expireTime < os.time() then
    request.err(401, 'The access token has expired.')
    return nil
  end

  -- Add token metadata to the request headers
  inject_req_headers(token_obj)

  -- keep token in cache until it expires
  local ttl = expireTime - os.time()
  local encodedToken = cjson.encode(token_obj)
  dataStore:saveOAuthToken(cache_key, token, encodedToken, ttl)
  return token_obj
end

return _M


