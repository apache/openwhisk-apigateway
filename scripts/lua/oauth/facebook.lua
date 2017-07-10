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
local request = require 'lib/request'
local cjson = require 'cjson'
local utils = require "lib/utils"

local _M = {}
function _M.process(dataStore, token)

  local headerName = utils.concatStrings({'http_', 'x-facebook-app-token'}):gsub("-", "_")

  local facebookAppToken = ngx.var[headerName]
  if facebookAppToken == nil then
    request.err(401, 'Facebook requires you provide an app token to validate user tokens. Provide a X-Facebook-App-Token header')
    return nil
  end

  local result = dataStore:getOAuthToken('facebook', token)
  if result ~= ngx.null then
    return cjson.decode(result)
  end
  result = dataStore:getOAuthToken('facebook', utils.concatStrings({token, facebookAppToken}))
  if result ~= ngx.null then
    return cjson.decode(result)
  end

   return exchangeOAuthToken(dataStore, token, facebookAppToken)
end

function exchangeOAuthToken(dataStore, token, facebookAppToken)
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
  -- convert Facebook's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  dataStore:saveOAuthToken('facebook', utils.concatStrings({token, facebookAppToken}), cjson.encode(json_resp), json_resp['expires_at'])
  return json_resp
end

return _M
