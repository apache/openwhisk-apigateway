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

--- @module apis
-- Management interface for apis for the gateway

local cjson = require "cjson"
local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"
local apis = require "management/lib/apis"
local tenants = require "management/lib/tenants"
local swagger = require "management/lib/swagger"
local validation = require "management/lib/validation"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

--- Request handler for routing API calls appropriately
function _M.requestHandler()
  local requestMethod = ngx.req.get_method()
  ngx.header.content_type = "application/json; charset=utf-8"
  if requestMethod == "GET" then
    getAPIs()
  elseif requestMethod == 'POST' or requestMethod == 'PUT' then
    addAPI()
  elseif requestMethod == "DELETE" then
    deleteAPI()
  else
    request.err(400, "Invalid verb.")
  end
end

function getAPIs()
  local queryParams = ngx.req.get_uri_args()
  local id = ngx.var.api_id
  local version = ngx.var.version
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  if id == '' then
    local apiList
    if version == 'v1' then
      apiList = apis.getAllAPIs(red, queryParams)
    elseif version == 'v2' then
      local tenantId = ngx.var.tenantId
      local v2ApiList = {}
      apiList = tenants.getTenantAPIs(red, tenantId, queryParams)
      for _, api in pairs(apiList) do
        v2ApiList[#v2ApiList+1] = {
          artifact_id = api.id,
          managed_url = api.managedUrl,
          open_api_doc = redis.getSwagger(red, api.id)
        }
      end
      apiList = v2ApiList
    end
    apiList = (next(apiList) == nil) and "[]" or cjson.encode(apiList)
    redis.close(red)
    request.success(200, apiList)
  else
    local query = ngx.var.query
    if query ~= '' then
      if query ~= "tenant" then
        redis.close(red)
        request.err(400, "Invalid request")
      else
        local tenant = apis.getAPITenant(red, id)
        tenant = cjson.encode(tenant)
        redis.close(red)
        request.success(200, tenant)
      end
    else
      local api = apis.getAPI(red, id)
      if version == 'v1' then
        redis.close(red)
        api = cjson.encode(api)
        request.success(200, api)
      elseif version == 'v2' then
        local returnObj = {
          artifact_id = api.id,
          managed_url = api.managedUrl,
          open_api_doc = redis.getSwagger(red, api.id)
        }
        redis.close(red)
        request.success(200, cjson.encode(returnObj))
      end
    end
  end
end

function addAPI()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local id = ngx.var.api_id
  local existingAPI = checkForExistingAPI(red, id)
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    redis.close(red)
    request.err(400, "Missing request body")
  end
  -- Convert json into Lua table
  local version = ngx.var.version
  local decoded
  local swaggerTable;
  if version == 'v1' then
    decoded = cjson.decode(args)
  elseif version == 'v2' then
    swaggerTable = cjson.decode(args)
    decoded = swagger.parseSwagger(swaggerTable)
    local tenantId = ngx.var.tenantId
    local tenant = {
      namespace = tenantId,
      instance = ''
    }
    tenants.addTenant(red, tenant, {id = tenantId})
    decoded.tenantId = tenantId
  end
  -- Check for api id in JSON body
  if existingAPI == nil and decoded.id ~= nil then
    existingAPI = redis.getAPI(red, decoded.id)
    if existingAPI == nil then
      redis.close(red)
      request.err(404, utils.concatStrings({"Unknown API id ", decoded.id}))
    end
  end
  local err = validation.validate(red, decoded)
  if err ~= nil then
    redis.close(red)
    request.err(err.statusCode, err.message)
  end
  local managedUrlObj = apis.addAPI(red, decoded, existingAPI)
  if version == 'v1' then
    redis.close(red)
    managedUrlObj = cjson.encode(managedUrlObj)
    request.success(200, managedUrlObj)
  elseif version == 'v2' then
    redis.addSwagger(red, managedUrlObj.id, swaggerTable)
    local returnObj = {
      artifact_id = managedUrlObj.id,
      managed_url = managedUrlObj.managedUrl,
      open_api_doc = swaggerTable
    }
    redis.close(red)
    request.success(200, cjson.encode(returnObj))
  end
end

function deleteAPI()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local id = ngx.var.api_id
  if id == nil or id == '' then
    redis.close(red)
    request.err(400, "No id specified.")
  end
  apis.deleteAPI(red, id)
  local version = ngx.var.version
  if version == 'v1' then
    redis.close(red)
    request.success(200, {})
  elseif version == 'v2' then
    redis.deleteSwagger(red, id)
    redis.close(red)
    request.success(204)
  end
end

--- Check for api id from uri and use existing API if it already exists in redis
-- @param red Redis client instance
-- @param id API id to check
function checkForExistingAPI(red, id)
  local existing
  if id ~= nil and id ~= '' then
    existing = redis.getAPI(red, id)
    if existing == nil then
      redis.close(red)
      request.err(404, utils.concatStrings({"Unknown API id ", id}))
    end
  end
  return existing
end

return _M;
