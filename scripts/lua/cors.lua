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

--- @module Cors
-- Used to set cors headers for preflight and simple requests

local _M = {}
local request = require "lib/request"

function _M.processCall(resourceConfig)
  if resourceConfig.cors ~= nil then
    _M.setCorsHeaders(resourceConfig.cors.origin, resourceConfig.cors.methods)
    if ngx.req.get_method() == "OPTIONS" then
      request.success(200)
    end
  end
end

function _M.setCorsHeaders(corsOrigin, corsMethods)
  if corsOrigin ~= nil then
    if corsOrigin == 'false' then
      ngx.header['Access-Control-Allow-Origin'] = nil
      ngx.header['Access-Control-Allow-Methods'] = nil
    else
      ngx.header['Access-Control-Allow-Origin'] = corsOrigin
      ngx.header['Access-Control-Allow-Headers'] = ngx.req.get_headers()['Access-Control-Request-Headers']
      if corsMethods ~= nil then
        ngx.header['Access-Control-Allow-Methods'] = corsMethods
      else
        ngx.header['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS'
      end
    end
  end
end

return _M
