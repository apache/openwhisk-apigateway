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
local utils = require "lib/utils"
local redis = require "lib/redis"

function validateOAuthToken (red, token)

  local headerName = utils.concatStrings({'http_', 'x-facebook-app-token'}):gsub("-", "_")

  local facebookAppToken = ngx.var[headerName]
  if facebookAppToken == nil then
    request.err(401, 'Facebook requires you provide an app token to validate user tokens. Provide a X-Facebook-App-Token header')
    return nil
  end

  local key = utils.concatStrings({'oauth:providers:facebook:tokens:', token})
  if redis.exists(red, key) == 1 then
    return cjson.decode(redis.get(red,key))
  end

  local key = utils.concatStrings({'oauth:providers:facebook:tokens:', token, facebookAppToken})
  if redis.exists(red, key) == 1 then
    return cjson.decode(redis.get(red, key))
  end
  return exchangeOAuthToken(red, token, facebookAppToken)
end

function exchangeOAuthToken(red, token, facebookAppToken)
  local http = require 'resty.http'
  local request = require "lib/request"
  local httpc = http.new()

  local request_options = {
    headers = {
      ['Accept'] = 'application/json'
    },
    ssl_verify = false
  }
  local envUrl = os.getenv('TOKEN_FACEBOOK_URL')
  envUrl = envUrl ~= nil and envUrl or 'https://graph.facebook.com/debug_token'
  local request_uri = utils.concatStrings({envUrl, '?input_token=', token,  '&access_token=', facebookAppToken})
  local res, err = httpc:request_uri(request_uri, request_options)
-- convert response
  if not res then
    ngx.log(ngx.WARN, 'Could not invoke Facebook API. Error=', err)
    request.err(500, 'OAuth provider error.')
    return
  end
  local json_resp = cjson.decode(res.body)

  if (json_resp['error']) then
    return nil
  end
  -- facebook uses a different expire field than others
  json_resp['expires'] = json_resp['expires_at']
  -- convert Facebook's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  redis.set(red, key, cjson.encode(json_resp))
  redis.expire(red, json_resp, json_resp['expires'])
  return json_resp
end

return validateOAuthToken

