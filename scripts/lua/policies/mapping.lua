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

--- @module mapping
-- Process mapping object, turning implementation details into request transformations
-- @author Cody Walker (cmwalker), Alex Song (songs), David Green (greend)

local logger = require "lib/logger"
local utils = require "lib/utils"
local cjson = require "cjson"

local _M = {}

local body = nil
local query = nil
local headers = nil
local path = nil

--- Implementation for the mapping policy.
-- @param map The mapping object that contains details about request tranformations
function processMap(map)
  getRequestParams()
  for k, v in pairs(map) do
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

--- Get request body, params, and headers from incoming requests
function getRequestParams()
  ngx.req.read_body()
  body = ngx.req.get_body_data()
  body = (body and cjson.decode(body)) or {}
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
function insertParam(m)
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
function removeParam(m)
  if m.from.location == "header" then
    removeHeader(m.from.name)
  elseif m.from.location == "query" then
    removeQuery(m.from.name)
  elseif m.from.location == "body" then
    removeBody(m.from.name)
  end
end

--- Move parameter value from one location to another in the request
-- @param m Parameter value to move within request
function transformParam(m)
  if m.from.name == '*' then
    transformAllParams(m.from.location, m.to.location)
  else
    insertParam(m)
    removeParam(m)
  end
end

--- Checks if the header has been set, and sets the header to a value if found to be null.
-- @param m Header name and value to be set, if header is null.
function checkDefault(m)
  if m.to.location == "header" and headers[m.to.name] == nil then
    insertHeader(m.to.name, m.from.value)
  elseif m.to.location == "query" and query[m.to.name] == nil then
    insertQuery(m.to.name, m.from.value)
  elseif m.to.location == "body" and body[m.to.name] == nil then
    insertBody(m.to.name, m.from.value)
  end
end

--- Function to handle wildcarding in the transform process.
-- If the value in the from object is '*', this function will pull all values from the incoming request
-- and move them to the location provided in the to object
-- @param s The source object from which we pull all parameters
-- @param d The destination object that we will move all found parameters to.
function transformAllParams(s, d)
  if s == 'query' then
    for k, v in pairs(query) do
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
    for k, v in pairs(headers) do
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
    for k, v in pairs(body) do
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
    for k, v in pairs(path) do
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

function finalize()
  local bodyJson = cjson.encode(body)
  ngx.req.set_body_data(bodyJson)
  ngx.req.set_uri_args(query)
end

function insertHeader(k, v)
  ngx.req.set_header(k, v)
  headers[k] = v
end

function insertQuery(k, v)
  query[k] = v
end

function insertBody(k, v)
  body[k] = v
end

function insertPath(k, v)
  v = ngx.unescape_uri(v)
  path = path:gsub(utils.concatStrings({"%{", k ,"%}"}), v)
  ngx.req.set_uri(path)
end

function removeHeader(k)
  ngx.req.clear_header(k)
end

function removeQuery(k)
  query[k] = nil
end

function removeBody(k)
  body[k] = nil
end

function parseUrl(url)
  local map = {}
  for k,v in url:gmatch('([^&=?]+)=([^&=?]+)') do
    map[ k ] = decodeQuery(v)
  end
  return map
end

function decodeQuery(param)
  local decoded = param:gsub('+', ' '):gsub('%%(%x%x)',
    function(hex) return string.char(tonumber(hex, 16)) end)
  return decoded
end

_M.processMap = processMap

return _M