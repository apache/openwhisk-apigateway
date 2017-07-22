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

function _M.process(dataStore, token, securityObj)
  local result = dataStore:getOAuthToken('appId', token)
  local httpc = http.new()
  local json_resp
  if result ~= ngx.null then
    json_resp = cjson.decode(result)
    ngx.header['X-OIDC-Email'] = json_resp['email']
    ngx.header['X-OIDC-Sub'] = json_resp['sub']
    return json_resp
  end
  local keyUrl = utils.concatStrings({APPID_PKURL, securityObj.tenantId, '/publickeys'})
  local request_options = {
    headers = {
      ["Accept"] = "application/json"
    },
    ssl_verify = false
  }
  local res, err = httpc:request_uri(keyUrl, request_options)
  if err then
    request.err(500, 'error getting app id key: ' .. err)
  end

  local key
  local keys = cjson.decode(res.body).keys
  for _, v in ipairs(keys) do
    key = v
  end
  local result = cjose.validateJWS(token, cjson.encode(key))
  if not result then
    request.err(401, 'AppId key signature verification failed.')
    return nil
  end
  jwt_obj = cjson.decode(cjose.getJWSInfo(token))
  ngx.header['X-OIDC-Email'] = jwt_obj['email']
  ngx.header['X-OIDC-Sub'] = jwt_obj['sub']
  dataStore:saveOAuthToken('appId', token, cjson.encode(jwt_obj), jwt_obj['exp'])
  return jwt_obj
end


return _M


