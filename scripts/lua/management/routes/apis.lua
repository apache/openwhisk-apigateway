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

--- @module apis
-- Management interface for apis for the gateway

local cjson = require "cjson"
local utils = require "lib/utils"
local request = require "lib/request"
local apis = require "management/lib/apis"
local tenants = require "management/lib/tenants"
local swagger = require "management/lib/swagger"
local validation = require "management/lib/validation"

local _M = {}

--- Check for api id from uri and use existing API if it already exists in redis
-- @param red Redis client instance
-- @param id API id to check
local function checkForExistingAPI(dataStore, id)
  local existing
  if id ~= nil and id ~= '' then
    existing = dataStore:getAPI(id)
    if existing == nil then
      dataStore:close()
      request.err(404, utils.concatStrings({"Unknown API id ", id}))
    end
  end
  return existing
end

local function getAPIs(dataStore)
  local queryParams = ngx.req.get_uri_args()
  local id = ngx.var.api_id
  local version = ngx.var.version
  if id == '' then
    local apiList
    if version == 'v1' then
      apiList = apis.getAllAPIs(dataStore, queryParams)
    elseif version == 'v2' then
      local tenantId = ngx.var.tenantId
      local v2ApiList = {}
      apiList = tenants.getTenantAPIs(dataStore, tenantId, queryParams)
      for _, api in pairs(apiList) do
        v2ApiList[#v2ApiList+1] = {
          artifact_id = api.id,
          managed_url = api.managedUrl,
          open_api_doc = dataStore:getSwagger(api.id)
        }
      end
      apiList = v2ApiList
    end
    apiList = (next(apiList) == nil) and "[]" or cjson.encode(apiList)
    dataStore:close()
    request.success(200, apiList)
  else
    local query = ngx.var.query
    if query ~= '' then
      if query ~= "tenant" then
        dataStore:close()
        request.err(400, "Invalid request")
      else
        local tenant = apis.getAPITenant(dataStore, id)
        tenant = cjson.encode(tenant)
        dataStore:close()
        request.success(200, tenant)
      end
    else
      local api = apis.getAPI(dataStore, id)
      if version == 'v1' then
        dataStore:close()
        api = cjson.encode(api)
        request.success(200, api)
      elseif version == 'v2' then
        local returnObj = {
          artifact_id = api.id,
          managed_url = api.managedUrl,
          open_api_doc = dataStore:getSwagger(api.id)
        }
        dataStore:close()
        request.success(200, cjson.encode(returnObj))
      end
    end
  end
end

local function addAPI(dataStore)
  local id = ngx.var.api_id
  local existingAPI = checkForExistingAPI(dataStore, id)
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    dataStore:close()
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
    tenants.addTenant(dataStore, tenant, {id = tenantId})
    decoded.tenantId = tenantId
  end
  -- Check for api id in JSON body
  if existingAPI == nil and decoded.id ~= nil then
    existingAPI = dataStore:getAPI(decoded.id)
    if existingAPI == nil then
      dataStore:close()
      request.err(404, utils.concatStrings({"Unknown API id ", decoded.id}))
    end
  end
  local err = validation.validate(dataStore, decoded)
  if err ~= nil then
    dataStore:close()
    request.err(err.statusCode, err.message)
  end
  local managedUrlObj = apis.addAPI(dataStore, decoded, existingAPI)
  if version == 'v1' then
    dataStore:close()
    managedUrlObj = cjson.encode(managedUrlObj)
    request.success(200, managedUrlObj)
  elseif version == 'v2' then
    dataStore:addSwagger(managedUrlObj.id, swaggerTable)
    local returnObj = {
      artifact_id = managedUrlObj.id,
      managed_url = managedUrlObj.managedUrl,
      open_api_doc = swaggerTable
    }
    dataStore:close()
    request.success(200, cjson.encode(returnObj))
  end
end

local function deleteAPI(dataStore)
  local id = ngx.var.api_id
  if id == nil or id == '' then
    dataStore:close()
    request.err(400, "No id specified.")
  end
  apis.deleteAPI(dataStore, id)
  local version = ngx.var.version
  if version == 'v1' then
    dataStore:close()
    request.success(200, cjson.encode({}))
  elseif version == 'v2' then
    dataStore:deleteSwagger(id)
    dataStore:close()
    request.success(204)
  end
end

--- Request handler for routing API calls appropriately
function _M.requestHandler(dataStore)
  local requestMethod = ngx.req.get_method()
  ngx.header.content_type = "application/json; charset=utf-8"
  if requestMethod == "GET" then
    getAPIs(dataStore)
  elseif requestMethod == 'POST' or requestMethod == 'PUT' then
    addAPI(dataStore)
  elseif requestMethod == "DELETE" then
    deleteAPI(dataStore)
  else
    request.err(400, "Invalid verb.")
  end
end

return _M;
