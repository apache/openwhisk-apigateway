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

-- A Proxy for Github OAuth API
local cjson = require "cjson"
local http = require "resty.http"
local httpc = http.new()
local request = require "lib/request"
local cjson = require "cjson"
local utils = require "lib/utils"

function validateOAuthToken (red, token)

  local key = utils.concatStrings({'oauth:provider:github:', token})
  if redis.exists(red, key) == 1 then
    redis.close(red)
    return cjson.decode(redis.get(red, key))
  end

  local request_options = {
    headers = {
      ["Accept"] = "application/json"
    },
    ssl_verify = false
  }

  local envUrl = os.getenv('TOKEN_GITHUB_URL')
  envUrl = envUrl ~= nil and envUrl or 'https://api.github.com/user'
  local request_uri = utils.concatStrings({envUrl, '?access_token=', token})
  local res, err = httpc:request_uri(request_uri, request_options)
-- convert response
  if not res then
    ngx.log(ngx.WARN, utils.concatStrings({"Could not invoke Github API. Error=", err}))
    request.err(500, 'OAuth provider error.')
    return
  end

  local json_resp = cjson.decode(res.body)
  if json_resp.id == nil then
    return nil
  end

  if (json_resp.error_description) then
    return nil
  end

  redis.set(red, key, cjson.encode(json_resp))
  -- convert Github's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  return json_resp
end

return validateOAuthToken


