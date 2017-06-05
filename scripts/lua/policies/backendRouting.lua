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

--- @module backendRouting
-- Used to set the backend Url either statically or dynamically

local url = require "url"
local utils = require "lib/utils"
local request = require "lib/request"
local logger = require "lib/logger"

local _M = {}

--- Set upstream based on the backendUrl
function _M.setRoute(backendUrl)
  local u = url.parse(backendUrl)
  if u.scheme == nil then
    u = url.parse(utils.concatStrings({'http://', backendUrl}))
  end
  ngx.var.backendUrl = backendUrl
  ngx.req.set_uri(getUriPath(u.path))
  setUpstream(u)
end

--- Set dynamic route based on the based on the header that is passed in
function _M.setDynamicRoute(obj)
  local whitelist = obj.whitelist
  for k in pairs(whitelist) do
    whitelist[k] = whitelist[k]:lower()
  end
  local header = obj.header ~= nil and obj.header or 'X-Cf-Forwarded-Url'
  local dynamicBackend = ngx.req.get_headers()[header]
  if dynamicBackend ~= nil and dynamicBackend ~= '' then
    local u = url.parse(dynamicBackend)
    if u.scheme == nil or u.scheme == '' then
      u = url.parse(utils.concatStrings({'http://', dynamicBackend}))
    end
    if utils.tableContains(whitelist, u.host) then
      ngx.req.set_uri(getUriPath(u.path))
      local query = ngx.req.get_uri_args()
      for k, v in pairs(u.query) do
        query[k] = v
      end
      ngx.req.set_uri_args(query)
      setUpstream(u)
    else
      request.err(403, 'Dynamic backend host not part of whitelist.')
    end
  else
    logger.info('Header for dynamic routing not found. Defaulting to backendUrl.')
  end
end

function getUriPath(backendPath)
  local gatewayPath = ngx.unescape_uri(ngx.var.gatewayPath)
  gatewayPath = gatewayPath:gsub('-', '%%-')
  local uri = string.gsub(ngx.var.request_uri, '?.*', '')
  local _, j = uri:find(gatewayPath)
  local incomingPath = ((j and uri:sub(j + 1)) or nil)
  -- Check for backendUrl path
  if backendPath == nil or backendPath == '' or backendPath == '/' then
    incomingPath = (incomingPath and incomingPath ~= '') and incomingPath or '/'
    incomingPath = string.sub(incomingPath, 1, 1) == '/' and incomingPath or utils.concatStrings({'/', incomingPath})
    return incomingPath
  else
    return utils.concatStrings({backendPath, incomingPath})
  end
end

function setUpstream(u)
  local upstream = utils.concatStrings({u.scheme, '://', u.host})
  if u.port ~= nil and u.port ~= '' then
    upstream = utils.concatStrings({upstream, ':', u.port})
  end
  ngx.var.upstream = upstream
end

return _M
