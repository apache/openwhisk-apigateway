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

--- @module Routing
-- Used to dynamically handle nginx routing based on an object containing implementation details
-- @author Cody Walker (cmwalker)


local logger = require "lib/logger"
local utils = require "lib/utils"
local url = require "url"
local cjson = require "cjson"
-- load policies
local security = require "policies/security"
local mapping = require "policies/mapping"
local rateLimit = require "policies/rateLimit"

local _M = {}

--- Main function that handles parsing of invocation details and carries out implementation
-- @param obj Lua table object containing implementation details for the given route
-- {
--   {{GatewayMethod (GET / PUT / POST / DELETE)}} = {
--      "backendMethod": (GET / PUT / POST / DELETE) - Method to use for invocation (if different from gatewayMethod),
--      "backendUrl": STRING - fully composed url of backend invocation,
--      "policies": LIST - list of table objects containing type and value fields
--    }, ...
-- }
function processCall(obj)
  local verb = ngx.req.get_method()
  local found = false
  for k, v in pairs(obj) do
    if k == verb then
      -- Check if auth is required
      if (v.security and string.lower(v.security.type) == 'apikey') then
        local h = v.security.header
        if h == nil then
          h = 'http_x_api_key'
        else
          h = utils.concatStrings({'http_', h})
        end
        security.processAPIKey(h:gsub("-", "_"))
      end
      local u = url.parse(v.backendUrl)
      ngx.req.set_uri(u.path)
      ngx.var.upstream = utils.concatStrings({u.scheme, '://', u.host})
      if v.backendMethod ~= nil then
        setVerb(v.backendMethod)
      end
      parsePolicies(v.policies)
      found = true
      break
    end
  end
  if found == false then
    ngx.say('Whoops. Verb not supported.')
    ngx.exit(404)
  end
end

--- Function to read the list of policies and send implementation to the correct backend
-- @param obj List of policies containing a type and value field. This function reads the type field and routes it appropriately.
function parsePolicies(obj)
  for k, v in pairs (obj) do
    if v.type == 'reqMapping' then
      mapping.processMap(v.value)
    elseif v.type == 'rateLimit' then
      rateLimit.limit(v.value)
    end
  end
end

--- Given a verb, transforms the backend request to use that method
-- @param v Verb to set on the backend request
function setVerb(v)
  if (string.lower(v) == 'post') then
    ngx.req.set_method(ngx.HTTP_POST)
  elseif (string.lower(v) == 'put') then
    ngx.req.set_method(ngx.HTTP_PUT)
  elseif (string.lower(v) == 'delete') then
    ngx.req.set_method(ngx.HTTP_DELETE)
  else
    ngx.req.set_method(ngx.HTTP_GET)
  end
end

_M.processCall = processCall

return _M