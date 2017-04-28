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
---
-- A Proxy for Google OAuth API
local cjson = require "cjson"
local http = require "resty.http"
local request = require "lib/request"
local utils = require "lib/utils"
local httpc = http.new()
local redis = require "lib/redis"

function validateOAuthToken (red, token)

  local key = utils.concatStrings({'oauth:provider:google:', token})
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
  local envUrl = os.getenv('TOKEN_GOOGLE_URL')
  envUrl = envUrl ~= nil and envUrl or 'https://www.googleapis.com/oauth2/v3/tokeninfo'
  local request_uri = utils.concatStrings({envUrl, "?access_token=", token})
  local res, err = httpc:request_uri(request_uri, request_options)
-- convert response
  if not res then
    ngx.log(ngx.WARN, utils.concatStrings({"Could not invoke Google API. Error=", err}))
    request.err(500, 'OAuth provider error.')
    return nil
  end
  local json_resp = cjson.decode(res.body)
 
  if (json_resp.error_description) then
    return nil
  end

  redis.set(red, key, cjson.encode(json_resp))
  redis.expire(red, key, json_resp['expires'])
  redis.close(red)
  -- convert Google's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  return json_resp
end

return validateOAuthToken


