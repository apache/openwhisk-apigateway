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

--- @module tenants
-- Management interface for tenants for the gateway

local cjson = require "cjson"
local redis = require "lib/redis"
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

--- Filter tenants based on query parameters
-- @param tenants list of tenants
-- @param queryParams query parameters to filter tenants
function filterTenants(tenants, queryParams)
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

--- Get APIs associated with tenant
-- @param ds redis client
-- @param id tenant id
-- @param queryParams object containing optional query parameters
function _M.getTenantAPIs(dataStore, id, queryParams)
  local apis = dataStore:getAllAPIs()
  local apiList
  if next(queryParams) ~= nil then
    apiList = filterTenantAPIs(id, apis, queryParams);
  end
  if apiList == nil then
    apiList = {}
    for k, v in pairs(apis) do
      if k%2 == 0 then
        local decoded = cjson.decode(v)
        if decoded.tenantId == id then
          apiList[#apiList+1] = decoded
        end
      end
    end
  end
  return apiList
end

--- Filter apis based on query paramters
-- @param queryParams query parameters to filter apis
function filterTenantAPIs(id, apis, queryParams)
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
  for k, v in pairs(apis) do
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
