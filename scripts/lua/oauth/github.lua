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
-- A Proxy for Github OAuth API
local cjson = require "cjson"
local http = require "resty.http"
local redis = require "lib/redis"
local request = require "lib/request"
local cjson = require "cjson"
local utils = require "lib/utils"
local _M = {}

function _M.process(dataStore, token)
  local result = dataStore:getOAuthToken('github', token)
  if result ~= ngx.null then
    json_resp = cjson.decode(result)
    ngx.header['X-OIDC-id'] = json_resp['id']
    ngx.header['X-OIDC-Email'] = json_resp['email']
    return json_resp
  end

  local request_options = {
    headers = {
      ["Accept"] = "application/json"
    },
    ssl_verify = false
  }

  local httpc = http.new()

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

  dataStore:saveOAuthToken('github', token, cjson.encode(json_resp))
  -- convert Github's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  ngx.header['X-OIDC-id'] = json_resp['id']
  ngx.header['X-OIDC-Email'] = json_resp['email']
  return json_resp
end

return _M
