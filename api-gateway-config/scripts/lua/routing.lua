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
-- @author Cody Walker (cmwalker), Alex Song (songs)


local utils = require "lib/utils"
local request = require "lib/request"
local url = require "url"
-- load policies
local security = require "policies/security"
local mapping = require "policies/mapping"
local rateLimit = require "policies/rateLimit"

local _M = {}

--- Main function that handles parsing of invocation details and carries out implementation
-- @param obj Lua table object containing implementation details for the given resource
-- {
--   {{GatewayMethod (GET / PUT / POST / DELETE)}} = {
--      "backendMethod": (GET / PUT / POST / DELETE) - Method to use for invocation (if different from gatewayMethod),
--      "backendUrl": STRING - fully composed url of backend invocation,
--      "policies": LIST - list of table objects containing type and value fields
--    }, ...
-- }
function processCall(obj)
  local found = false
  for verb, opFields in pairs(obj.operations) do
    if string.upper(verb) == ngx.req.get_method() then
      -- Check if auth is required
      local apiKey
      if (opFields.security and string.lower(opFields.security.type) == 'apikey') then
        apiKey = security.processAPIKey(opFields.security)
      end
      -- Parse backend url
      local u = url.parse(opFields.backendUrl)
      ngx.req.set_uri(getUriPath(u.path))
      ngx.var.backendUrl = opFields.backendUrl
      -- Set upstream - add port if it's in the backendURL
      local upstream = utils.concatStrings({u.scheme, '://', u.host})
      if u.port ~= nil and u.port ~= '' then
        upstream = utils.concatStrings({upstream, ':', u.port})
      end
      ngx.var.upstream = upstream
      -- Set backend method
      if opFields.backendMethod ~= nil then
        setVerb(opFields.backendMethod)
      end
      -- Parse policies
      if opFields.policies ~= nil then
        parsePolicies(opFields.policies, apiKey)
      end
      found = true
      break
    end
  end
  if found == false then
    request.err(404, 'Whoops. Verb not supported.')
  end
end

--- Function to read the list of policies and send implementation to the correct backend
-- @param obj List of policies containing a type and value field. This function reads the type field and routes it appropriately.
-- @param apiKey optional subscription api key
function parsePolicies(obj, apiKey)
  for k, v in pairs (obj) do
    if v.type == 'reqMapping' then
      mapping.processMap(v.value)
    elseif v.type == 'rateLimit' then
      rateLimit.limit(v.value, apiKey)
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
  elseif (string.lower(v) == 'patch') then
      ngx.req.set_method(ngx.HTTP_PATH)
  elseif (string.lower(v) == 'head') then
      ngx.req.set_method(ngx.HTTP_HEAD)
  elseif (string.lower(v) == 'options') then
      ngx.req.set_method(ngx.HTTP_OPTIONS)
  else
    ngx.req.set_method(ngx.HTTP_GET)
  end
end

function getUriPath(backendPath)
  local uriPath
  local i, j = ngx.var.uri:find(ngx.var.gatewayPath)
  local incomingPath = ((j and ngx.var.uri:sub(j + 1)) or nil)
  -- Check for backendUrl path
  if backendPath == nil or backendPath== '' or backendPath== '/' then
    uriPath = (incomingPath and incomingPath ~= '') and incomingPath or '/'
  else
    uriPath = utils.concatStrings({backendPath, incomingPath})
  end
  return uriPath
end

_M.processCall = processCall

return _M
