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

--- @module mapping
-- Process mapping object, turning implementation details into request transformations

local logger = require "lib/logger"
local utils = require "lib/utils"
local cjson = require "cjson.safe"
cjson.decode_array_with_array_mt(true)

local _M = {}

local body
local query
local headers
local path

local function insertHeader(k, v)
  ngx.req.set_header(k, v)
  headers[k] = v
end

local function insertQuery(k, v)
  query[k] = v
end

local function insertBody(k, v)
  body[k] = v
end

local function insertPath(k, v)
  v = ngx.unescape_uri(v)
  path = path:gsub(utils.concatStrings({"%{", k ,"%}"}), v)
  ngx.req.set_uri(path)
end

local function removeHeader(k)
  ngx.req.clear_header(k)
end

local function removeQuery(k)
  query[k] = nil
end

local function removeBody(k)
  body[k] = nil
end

local function decodeQuery(param)
  local decoded = param:gsub('+', ' '):gsub('%%(%x%x)',
    function(hex) return string.char(tonumber(hex, 16)) end)
  return decoded
end

local function parseUrl(url)
  local map = {}
  for k,v in url:gmatch('([^&=?]+)=([^&=?]+)') do
    map[ k ] = decodeQuery(v)
  end
  return map
end

--- Get request body, params, and headers from incoming requests
local function getRequestParams()
  ngx.req.read_body()
  body = ngx.req.get_body_data()
  if body ~= nil then
    -- decode body if json
    local decoded, err = cjson.decode(body)
    if err == nil then
      body = decoded
    end
  else
    body = {}
  end
  headers = ngx.req.get_headers()
  path = ngx.var.uri
  query = parseUrl(ngx.var.backendUrl)
  local incomingQuery = ngx.req.get_uri_args()
  for k, v in pairs (incomingQuery) do
    query[k] = v
  end
end

--- Insert parameter value to header, body, or query params into request
-- @param m Parameter value to add to request
local function insertParam(m)
  local v
  local k = m.to.name
  if m.from.value ~= nil then
    v = m.from.value
  elseif m.from.location == 'header' then
    v = headers[m.from.name]
  elseif m.from.location == 'query' then
    v = query[m.from.name]
  elseif m.from.location == 'body' then
    v = body[m.from.name]
  elseif m.from.location == 'path' then
    v = ngx.ctx[m.from.name]
  end
  -- determine to where
  if m.to.location == 'header' then
    insertHeader(k, v)
  elseif m.to.location == 'query' then
    insertQuery(k, v)
  elseif m.to.location == 'body' then
    insertBody(k, v)
  elseif m.to.location == 'path' then
    insertPath(k,v)
  end
end

--- Remove parameter value to header, body, or query params from request
-- @param m Parameter value to remove from request
local function removeParam(m)
  if m.from.location == "header" then
    removeHeader(m.from.name)
  elseif m.from.location == "query" then
    removeQuery(m.from.name)
  elseif m.from.location == "body" then
    removeBody(m.from.name)
  end
end

--- Function to handle wildcarding in the transform process.
-- If the value in the from object is '*', this function will pull all values from the incoming request
-- and move them to the location provided in the to object
-- @param s The source object from which we pull all parameters
-- @param d The destination object that we will move all found parameters to.
local function transformAllParams(s, d)
  if s == 'query' then
    for k in pairs(query) do
      local t = {}
      t.from = {}
      t.from.name = k
      t.from.location = s
      t.to = {}
      t.to.name = k
      t.to.location = d
      insertParam(t)
      removeParam(t)
    end
  elseif s == 'header' then
    for k in pairs(headers) do
      local t = {}
      t.from = {}
      t.from.name = k
      t.from.location = s
      t.to = {}
      t.to.name = k
      t.to.location = d
      insertParam(t)
      removeParam(t)
    end
  elseif s == 'body' then
    for k in pairs(body) do
      local t = {}
      t.from = {}
      t.from.name = k
      t.from.location = s
      t.to = {}
      t.to.name = k
      t.to.location = d
      insertParam(t)
      removeParam(t)
    end
  elseif s == 'path' then
    for k in pairs(path) do
      local t = {}
      t.from = {}
      t.from.name = k
      t.from.location = s
      t.to = {}
      t.to.name = k
      t.to.location = d
      insertParam(t)
      removeParam(t)
    end
  end
end

--- Move parameter value from one location to another in the request
-- @param m Parameter value to move within request
local function transformParam(m)
  if m.from.name == '*' then
    transformAllParams(m.from.location, m.to.location)
  else
    insertParam(m)
    removeParam(m)
  end
end

--- Checks if the header has been set, and sets the header to a value if found to be null.
-- @param m Header name and value to be set, if header is null.
local function checkDefault(m)
  if m.to.location == "header" and headers[m.to.name] == nil then
    insertHeader(m.to.name, m.from.value)
  elseif m.to.location == "query" and query[m.to.name] == nil then
    insertQuery(m.to.name, m.from.value)
  elseif m.to.location == "body" and body[m.to.name] == nil then
    insertBody(m.to.name, m.from.value)
  end
end

local function finalize()
  if type(body) == 'table' and next(body) ~= nil then
    local bodyJson = cjson.encode(body)
    ngx.req.set_body_data(bodyJson)
  end
  ngx.req.set_uri_args(query)
end

--- Implementation for the mapping policy.
-- @param map The mapping object that contains details about request transformations
local function processMap(map)
  getRequestParams()
  for _, v in pairs(map) do
    if v.action == "insert" then
      insertParam(v)
    elseif v.action == "remove" then
      removeParam(v)
    elseif v.action == "transform" then
      transformParam(v)
    elseif v.action == "default" then
      checkDefault(v)
    else
      logger.err(utils.concatStrings({'Map action not recognized. Skipping... ', v.action}))
    end
  end
  finalize()
end

_M.processMap = processMap

return _M
