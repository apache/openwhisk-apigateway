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

local cjson = require 'cjson'
local utils = require "lib/utils"

function validateOAuthToken (token)

  local headerName = utils.concatStrings({'http_', 'x-facebook-app-token'}):gsub("-", "_")
 
  local facebookAppToken = ngx.var[headerName]
  if facebookAppToken == nil then
    request.err(401, 'Facebook requires you provide an app token to validate user tokens. Provide a X-Facebook-App-Token header')
    return nil
  end
  if token == "token" and facebookAppToken == "app" then
    return [[
      {
        "token":"good"
      }
    ]]
  end
  return nil
end

return validateOAuthToken

