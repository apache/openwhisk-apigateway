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

local cjson = require "cjson"
local utils = require "lib/utils"
local request = require "lib/request"
local redis = require "lib/redis"
local url = require "url"
-- load policies
local security = require "policies/security"
local mapping = require "policies/mapping"
local rateLimit = require "policies/rateLimit"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

--- Main function that handles parsing of invocation details and carries out implementation
function _M.processCall()
  -- Get resource object from redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local resourceKeys = redis.getAllResourceKeys(red, ngx.var.tenant)
  local redisKey = _M.findRedisKey(resourceKeys, ngx.var.tenant, ngx.var.gatewayPath)
  if redisKey == nil then
    return request.err(404, 'Not found.')
  end
  local obj = cjson.decode(redis.getResource(red, redisKey, "resources"))
  local found = false
  for verb, opFields in pairs(obj.operations) do
    if string.upper(verb) == ngx.req.get_method() then
      -- Check if auth is required
      local key
      if (opFields.security) then
        for k, sec in ipairs(opFields.security) do  
          key = security.process(sec)
        end
      end
      -- Parse backend url
      local u = url.parse(opFields.backendUrl)
      -- add http:// if no protocol is specified
      if u.scheme == nil then
        u = url.parse(utils.concatStrings({'http://', opFields.backendUrl}))
      end
      ngx.req.set_uri(getUriPath(u.path))
      ngx.var.backendUrl = opFields.backendUrl
      -- Set upstream
      local upstream = utils.concatStrings({u.scheme, '://', u.host})
      -- add port if it's in the backendURL
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
        parsePolicies(opFields.policies, key)
      end
      found = true
      break
    end
  end
  if found == false then
    request.err(404, 'Whoops. Verb not supported.')
  end
end

--- Find the correct redis key based on the path that's passed in
-- @param resourceKeys list of resourceKeys to search through
-- @param tenant tenantId
-- @param path path to look for
function _M.findRedisKey(resourceKeys, tenant, path)
  -- Construct a table of redisKeys based on number of slashes in the path
  local keyTable = {}
  for i, key in pairs(resourceKeys) do
    local _, count = string.gsub(key, "/", "")
    -- handle cases where resource path is "/"
    if count == 1 and string.sub(key, -1) == "/" then
      count = count - 1
    end
    count = tostring(count)
    if keyTable[count] == nil then
      keyTable[count] = {}
    end
    table.insert(keyTable[count], key)
  end
  -- Find the correct redisKey
  local redisKey = utils.concatStrings({"resources:", tenant, ":", path})
  local _, count = string.gsub(redisKey, "/", "")
  for i = count, 0, -1 do
    local countString = tostring(i)
    if keyTable[countString] ~= nil then
      for _, key in pairs(keyTable[countString]) do
        -- Check for exact match or path parameter match
        if key == redisKey or key == utils.concatStrings({redisKey, "/"}) or _M.pathParamMatch(key, redisKey) == true then
          local res = {string.match(key, "([^:]+):([^:]+):([^:]+)")}
          ngx.var.gatewayPath = res[3]
          return key
        end
      end
    end
    -- substring redisKey upto last "/"
    local index = redisKey:match("^.*()/")
    if index == nil then
      return nil
    end
    redisKey = string.sub(redisKey, 1, index - 1)
  end
  return nil
end

--- Check redis if resourceKey matches path parameters
-- @param key key that may have path parameter variables
-- @param resourceKey redis resourceKey to check if it matches path parameter
function _M.pathParamMatch(key, resourceKey)
  local pathParamVars = {}
  for w in string.gfind(key, "({%w+})") do
    w = string.sub(w, 2, string.len(w) - 1)
    pathParamVars[#pathParamVars + 1] = w
  end
  if next(pathParamVars) ~= nil then
    local pathPattern, count = string.gsub(key, "%{(%w*)%}", "([^:]+)")
    pathPattern = string.gsub(pathPattern, "%-", "%%-")
    local obj = {string.match(resourceKey, pathPattern)}
    if (#obj == count) then
      for i, v in pairs(obj) do
        ngx.ctx[pathParamVars[i]] = v
      end
      return true
    end
  end
  return false
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
  local allowedVerbs = {'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'}
  local verb = string.upper(v)
  if(utils.tableContains(allowedVerbs, verb)) then
    ngx.req.set_method(ngx[utils.concatStrings({"HTTP_", verb})])
  else
    ngx.req.set_method(ngx.HTTP_GET)
  end
end

function getUriPath(backendPath)
  local gatewayPath = ngx.unescape_uri(ngx.var.gatewayPath)
  gatewayPath = gatewayPath:gsub('-', '%%-')
  local _, j = ngx.var.uri:find(gatewayPath)
  local incomingPath = ((j and ngx.var.uri:sub(j + 1)) or nil)
  -- Check for backendUrl path
  if backendPath == nil or backendPath == '' or backendPath == '/' then
    incomingPath = (incomingPath and incomingPath ~= '') and incomingPath or '/'
    incomingPath = string.sub(incomingPath, 1, 1) == '/' and incomingPath or utils.concatStrings({'/', incomingPath})
    return incomingPath
  else
    return utils.concatStrings({backendPath, incomingPath})
  end
end

return _M
