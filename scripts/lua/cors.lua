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

--- @module Cors
-- Used to set cors headers for preflight and simple requests

local _M = {}
local request = require 'lib/request'

function _M.processCall(resourceConfig)
  if resourceConfig.cors ~= nil then
    ngx.var.cors_origins = resourceConfig.cors.origin
    ngx.var.cors_methods = resourceConfig.cors.methods
    -- preflight options call
    if resourceConfig.cors.origin ~= 'false' and ngx.req.get_method() == 'OPTIONS' then
      -- 'Access-Control-Allow-Headers' response header is required for preflight requests that have 'Access-Control-Request-Headers' headers
      local accessControlRequestHeaders = ngx.req.get_headers()['Access-Control-Request-Headers']
      if accessControlRequestHeaders ~= nil then
        ngx.header['Access-Control-Allow-Headers'] = accessControlRequestHeaders
      end
      request.success(200)
    end
  end
end

function _M.replaceHeaders()
  if ngx.var.cors_origins ~= nil and ngx.var.cors_origins ~= '' then
    if ngx.var.cors_origins == 'false' then
      ngx.header['Access-Control-Allow-Origin'] = nil
      ngx.header['Access-Control-Allow-Methods'] = nil
      ngx.header['Access-Control-Allow-Headers'] = nil
      ngx.header['Access-Control-Allow-Credentials'] = nil
      ngx.header['Access-Control-Expose-Headers'] = nil
      ngx.header['Access-Control-Max-Age'] = nil
    else
      ngx.header['Access-Control-Allow-Origin'] = ngx.var.cors_origins == 'true' and (ngx.var.http_origin or '*') or ngx.var.cors_origins
      ngx.header['Access-Control-Allow-Methods'] = ngx.var.cors_methods or 'GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS'
      ngx.header['Access-Control-Allow-Credentials'] = 'true'
    end
  end
end

return _M
