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

--- @module tenants
-- Management interface for tenants for the gateway

local cjson = require "cjson"
local utils = require "lib/utils"
local request = require "lib/request"
local apis = require "management/lib/apis"

local _M = {};

function _M.addTenant(dataStore, decoded, existingTenant)
  -- Return tenant object
  local uuid = existingTenant ~= nil and existingTenant.id or utils.uuid()
  local tenantObj = {
    id = uuid,
    namespace = decoded.namespace,
    instance = decoded.instance
  }
  tenantObj = dataStore:addTenant(uuid, tenantObj)
  return cjson.decode(tenantObj)
end

--- Filter tenants based on query parameters
-- @param tenants list of tenants
-- @param queryParams query parameters to filter tenants
local function filterTenants(tenants, queryParams)
  local namespace = queryParams['filter[where][namespace]']
  local instance = queryParams['filter[where][instance]']
  -- missing or invalid query parameters
  if (namespace == nil and instance == nil) or (instance ~= nil and namespace == nil) then
    return nil
  end
  -- filter tenants
  local tenantList = {}
  for k, v in pairs(tenants) do
    if k%2 == 0 then
      local tenant = cjson.decode(v)
      if (namespace ~= nil and instance == nil and tenant.namespace == namespace) or
          (namespace ~= nil and instance ~= nil and tenant.namespace == namespace and tenant.instance == instance) then
        tenantList[#tenantList+1] = tenant
      end
    end
  end
  return tenantList
end

--- Get all tenants in redis
-- @param ds redis client
-- @param queryParams object containing optional query parameters
function _M.getAllTenants(dataStore, queryParams)
  local tenants = dataStore:getAllTenants()
  local tenantList
  if next(queryParams) ~= nil then
    tenantList = filterTenants(tenants, queryParams);
  end
  if tenantList == nil then
    tenantList = {}
    for k, v in pairs(tenants) do
      if k%2 == 0 then
        tenantList[#tenantList+1] = cjson.decode(v)
      end
    end
  end
  return tenantList
end

--- Get tenant by its id
-- @param ds redis client
-- @param id tenant id
function _M.getTenant(dataStore, id)
  local tenant = dataStore:getTenant(id)
  if tenant == nil then
    request.err(404, utils.concatStrings({"Unknown tenant id ", id }))
  end
  return tenant
end

-- Apply paging on apis
-- @param apis the list of apis
-- @param queryparams object containing optional query parameters
local function applyPagingToAPIs(apiList, queryParams)
  local skip  = queryParams['skip']  == nil and 1 or queryParams['skip']
  local limit = queryParams['limit'] == nil and table.getn(apiList) or queryParams['limit']

  skip = tonumber(skip)
  limit = tonumber(limit)

  if (limit == nil or limit < 1) then
    return {}
  end
  if (skip == nil or skip <= 0) then
    skip = 1
  else
    skip = skip + 1
  end
  if ((skip + limit - 1) > table.getn(apiList)) then
    limit = table.getn(apiList)
  else
    limit = skip + limit - 1
  end
  local apis_obj  = {}
  local idx   = 0
  for i = skip, limit do
    apis_obj[idx] = apiList[i]
    idx = idx + 1
  end
  return apis_obj
end

--- Filter apis based on query paramters
-- @param queryParams query parameters to filter apis
local function filterTenantAPIs(id, apis_obj, queryParams)
  local basePath = queryParams['filter[where][basePath]']
  basePath = basePath == nil and queryParams['basePath'] or basePath
  local name = queryParams['filter[where][name]']
  name = name == nil and queryParams['title'] or name
  -- missing query parameters
  if (basePath == nil and name == nil)then
    return nil
  end
  -- filter apis
  local apiList = {}
  for k, v in pairs(apis_obj) do
    if k%2 == 0 then
      local api = cjson.decode(v)
      if api.tenantId == id and
          ((basePath ~= nil and name == nil and api.basePath == basePath) or
              (name ~= nil and basePath == nil and api.name == name) or
              (basePath ~= nil and name ~= nil and api.basePath == basePath and api.name == name)) then
        apiList[#apiList+1] = api
      end
    end
  end
  return apiList
end

--- Get APIs associated with tenant
-- @param ds redis client
-- @param id tenant id
-- @param queryParams object containing optional query parameters
function _M.getTenantAPIs(dataStore, id, queryParams)
  local apis_obj = dataStore:getAllAPIs()
  local apiList
  if next(queryParams) ~= nil then
    apiList = filterTenantAPIs(id, apis_obj, queryParams);
  end
  if apiList == nil then
    apiList = {}
    for k, v in pairs(apis_obj) do
      if k%2 == 0 then
        local decoded = cjson.decode(v)
        if decoded.tenantId == id then
          apiList[#apiList+1] = decoded
        end
      end
    end
  end
  if (((queryParams['skip'] == nil or queryParams['skip'] == 'undefined') and (queryParams['limit'] == nil or queryParams['limit'] == 'undefined')) or table.getn(apiList) == 0) then
    return apiList
  else
    return applyPagingToAPIs(apiList, queryParams)
  end
end

--- Delete tenant from gateway
-- @param ds redis client
-- @param id id of tenant to delete
function _M.deleteTenant(dataStore, id)
  local tenantAPIs = _M.getTenantAPIs(dataStore, id, {})
  for _, v in pairs(tenantAPIs) do
    apis.deleteAPI(dataStore, v.id)
  end
  dataStore:deleteTenant(id)
  return {}
end

return _M
