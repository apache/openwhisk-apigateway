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
