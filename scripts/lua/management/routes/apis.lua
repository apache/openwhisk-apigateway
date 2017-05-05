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
local dataStore = require "lib/dataStore"
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
function _M.requestHandler(ds)
  local requestMethod = ngx.req.get_method()
  ngx.header.content_type = "application/json; charset=utf-8"
  if requestMethod == "GET" then
    getAPIs(ds)
  elseif requestMethod == 'POST' or requestMethod == 'PUT' then
    addAPI(ds)
  elseif requestMethod == "DELETE" then
    deleteAPI(ds)
  else
    request.err(400, "Invalid verb.")
  end
end

function getAPIs(ds)
  local queryParams = ngx.req.get_uri_args()
  local id = ngx.var.api_id
  local version = ngx.var.version
  if id == '' then
    local apiList
    if version == 'v1' then
      apiList = apis.getAllAPIs(ds, queryParams)
    elseif version == 'v2' then
      local tenantId = ngx.var.tenantId
      local v2ApiList = {}
      apiList = tenants.getTenantAPIs(ds, tenantId, queryParams)
      for _, api in pairs(apiList) do
        v2ApiList[#v2ApiList+1] = {
          artifact_id = api.id,
          managed_url = api.managedUrl,
          open_api_doc = dataStore.getSwagger(ds, api.id)
        }
      end
      apiList = v2ApiList
    end
    apiList = (next(apiList) == nil) and "[]" or cjson.encode(apiList)
    dataStore.close(ds)
    request.success(200, apiList)
  else
    local query = ngx.var.query
    if query ~= '' then
      if query ~= "tenant" then
        dataStore.close(ds)
        request.err(400, "Invalid request")
      else
        local tenant = apis.getAPITenant(ds, id)
        tenant = cjson.encode(tenant)
        dataStore.close(ds)
        request.success(200, tenant)
      end
    else
      local api = apis.getAPI(ds, id)
      if version == 'v1' then
        dataStore.close(ds)
        api = cjson.encode(api)
        request.success(200, api)
      elseif version == 'v2' then
        local returnObj = {
          artifact_id = api.id,
          managed_url = api.managedUrl,
          open_api_doc = dataStore.getSwagger(ds, api.id)
        }
        dataStore.close(ds)
        request.success(200, cjson.encode(returnObj))
      end
    end
  end
end

function addAPI(ds)
  local id = ngx.var.api_id
  local existingAPI = checkForExistingAPI(ds, id)
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    dataStore.close(ds)
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
    tenants.addTenant(ds, tenant, {id = tenantId})
    decoded.tenantId = tenantId
  end
  -- Check for api id in JSON body
  if existingAPI == nil and decoded.id ~= nil then
    existingAPI = dataStore.getAPI(ds, decoded.id)
    if existingAPI == nil then
      dataStore.close(ds)
      request.err(404, utils.concatStrings({"Unknown API id ", decoded.id}))
    end
  end
  local err = validation.validate(ds, decoded)
  if err ~= nil then
    dataStore.close(ds)
    request.err(err.statusCode, err.message)
  end
  local managedUrlObj = apis.addAPI(ds, decoded, existingAPI)
  if version == 'v1' then
    dataStore.close(ds)
    managedUrlObj = cjson.encode(managedUrlObj)
    request.success(200, managedUrlObj)
  elseif version == 'v2' then
    dataStore.addSwagger(ds, managedUrlObj.id, swaggerTable)
    local returnObj = {
      artifact_id = managedUrlObj.id,
      managed_url = managedUrlObj.managedUrl,
      open_api_doc = swaggerTable
    }
    dataStore.close(ds)
    request.success(200, cjson.encode(returnObj))
  end
end

function deleteAPI(ds)
  local id = ngx.var.api_id
  if id == nil or id == '' then
    dataStore.close(ds)
    request.err(400, "No id specified.")
  end
  apis.deleteAPI(ds, id)
  local version = ngx.var.version
  if version == 'v1' then
    dataStore.close(ds)
    request.success(200, cjson.encode({}))
  elseif version == 'v2' then
    dataStore.deleteSwagger(ds, id)
    dataStore.close(ds)
    request.success(204)
  end
end

--- Check for api id from uri and use existing API if it already exists in redis
-- @param red Redis client instance
-- @param id API id to check
function checkForExistingAPI(ds, id)
  local existing
  if id ~= nil and id ~= '' then
    existing = dataStore.getAPI(ds, id)
    if existing == nil then
      dataStore.close(ds)
      request.err(404, utils.concatStrings({"Unknown API id ", id}))
    end
  end
  return existing
end

return _M;
