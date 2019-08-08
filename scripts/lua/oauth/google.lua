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

-- A Proxy for Google OAuth API
local cjson = require "cjson"
local http = require "resty.http"
local request = require "lib/request"
local utils = require "lib/utils"
local redis = require "lib/redis"

local _M = {}
function _M.process (dataStore, token)

  local result = dataStore:getOAuthToken('google', token)

  local httpc = http.new()
  if result ~= ngx.null then
    json_resp = cjson.decode(result)
    ngx.header['X-OIDC-Sub'] = json_resp['sub']
    ngx.header['X-OIDC-Email'] = json_resp['email']
    ngx.header['X-OIDC-Scope'] = json_resp['scope']
    return json_resp
  end

  local request_options = {
    headers = {
      ["Accept"] = "application/json"
    },
    ssl_verify = false
  }

  local envUrl = os.getenv('TOKEN_GOOGLE_URL')
  envUrl = envUrl ~= nil and envUrl or 'https://www.googleapis.com/oauth2/v3/tokeninfo'
  local request_uri = utils.concatStrings({envUrl, "?access_token=", token})
  local res, err = httpc:request_uri(request_uri, request_options)
-- convert response
  if not res then
    ngx.log(ngx.WARN, utils.concatStrings({"Could not invoke Google API. Error=", err}))
    request.err(500, 'Connection to the OAuth provider failed.')
    return nil
  end
  local json_resp = cjson.decode(res.body)
  if json_resp['error_description'] ~= nil then
    return nil
  end

  -- keep token in cache until it expires
  local ttl = json_resp['expires_in']
  dataStore:saveOAuthToken('google', token, cjson.encode(json_resp), ttl)
  -- convert Google's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  ngx.header['X-OIDC-Sub'] = json_resp['sub']
  ngx.header['X-OIDC-Email'] = json_resp['email']
  ngx.header['X-OIDC-Scope'] = json_resp['scope']
  return json_resp
end

return _M
