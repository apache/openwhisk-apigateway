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
-- Module for querying APIs

local cjson = require "cjson"
local utils = require "lib/utils"
local request = require "lib/request"
local resources = require "management/lib/resources"

local MANAGEDURL_HOST = os.getenv("PUBLIC_MANAGEDURL_HOST")
MANAGEDURL_HOST = (MANAGEDURL_HOST ~= nil and MANAGEDURL_HOST ~= '') and MANAGEDURL_HOST or "0.0.0.0"
local MANAGEDURL_PORT = os.getenv("PUBLIC_MANAGEDURL_PORT")
MANAGEDURL_PORT = (MANAGEDURL_PORT ~= nil and MANAGEDURL_PORT ~= '') and MANAGEDURL_PORT or "8080"

local _M = {}

--- Get all APIs in redis
-- @param ds dataStore.client
-- @param queryParams object containing optional query parameters
function _M.getAllAPIs(dataStore, queryParams)
  local apis = dataStore:getAllAPIs()
  local apiList
  if next(queryParams) ~= nil then
    apiList = filterAPIs(apis, queryParams);
  end
  if apiList == nil then
    apiList = {}
    for k, v in pairs(apis) do
      if k%2 == 0 then
        apiList[#apiList+1] = cjson.decode(v)
      end
    end
  end
  return apiList
end

--- Get API by its id
-- @param ds dataStore.client
-- @param id of API
function _M.getAPI(dataStore, id)
  local api = dataStore:getAPI(id)
  if api == nil then
    request.err(404, utils.concatStrings({"Unknown api id ", id}))
  end
  return api
end

--- Get belongsTo relation tenant
-- @param ds dataStore.client
-- @param id id of API
function _M.getAPITenant(dataStore, id)
  local api = dataStore:getAPI(id)
  if api == nil then
    request.err(404, utils.concatStrings({"Unknown api id ", id}))
  end
  local tenantId = api.tenantId
  local tenant = dataStore:getTenant(tenantId)
  if tenant == nil then
    request.err(404, utils.concatStrings({"Unknown tenant id ", tenantId}))
  end
  return tenant
end

--- Add API to redis
-- @param ds dataStore.client
-- @param decoded JSON body as a lua table
-- @param existingAPI optional existing API for updates
function _M.addAPI(dataStore, decoded, existingAPI)
  -- Format basePath
  local basePath = decoded.basePath:sub(1,1) == '/' and decoded.basePath:sub(2) or decoded.basePath
  basePath = basePath:sub(-1) == '/' and basePath:sub(1, -2) or basePath
  -- Create managedUrl object
  local uuid = existingAPI ~= nil and existingAPI.id or utils.uuid()
  local managedUrl = utils.concatStrings({"http://", MANAGEDURL_HOST, ":", MANAGEDURL_PORT, "/api/", decoded.tenantId})
  if basePath:sub(1,1) ~= '' then
    managedUrl = utils.concatStrings({managedUrl, "/", basePath})
  end
  local tenantObj = dataStore:getTenant(decoded.tenantId)
  local managedUrlObj = {
    id = uuid,
    name = decoded.name,
    basePath = utils.concatStrings({"/", basePath}),
    tenantId = decoded.tenantId,
    tenantNamespace = tenantObj.namespace,
    tenantInstance = tenantObj.instance,
    resources = decoded.resources,
    managedUrl = managedUrl
  }
  -- Add API object to redis
  managedUrlObj = dataStore:addAPI(uuid, managedUrlObj, existingAPI)
  -- Add resources to redis
  for path, resource in pairs(decoded.resources) do
    local gatewayPath = utils.concatStrings({basePath, path})
    gatewayPath = (gatewayPath:sub(1,1) == '/') and gatewayPath:sub(2) or gatewayPath
    resource.apiId = uuid
    print('creating resource: ' .. cjson.encode(resource) .. 'path: ' .. gatewayPath .. 'tenantobj' .. cjson.encode(tenantObj))
    resources.addResource(dataStore, resource, gatewayPath, tenantObj)
  end
  return managedUrlObj
end

--- Delete API from gateway
-- @param ds dataStore.client
-- @param id id of API to delete
function _M.deleteAPI(dataStore, id)
  local api = dataStore:getAPI(id)
  if api == nil then
    request.err(404, utils.concatStrings({"Unknown API id ", id}))
  end
  -- Delete API
  dataStore:deleteAPI(id)
  -- Delete all resources for the API
  local basePath = api.basePath:sub(2)
  for path in pairs(api.resources) do
    local gatewayPath = utils.concatStrings({basePath, path})
    gatewayPath = (gatewayPath:sub(1,1) == '/') and gatewayPath:sub(2) or gatewayPath
    resources.deleteResource(dataStore, gatewayPath, api.tenantId)
  end
  return {}
end

--- Filter APIs based on query parameters
-- @param apis list of apis
-- @param queryParams query parameters to filter tenants
function filterAPIs(apis, queryParams)
  local basePath = queryParams['filter[where][basePath]']
  basePath = basePath == nil and queryParams['basePath'] or basePath
  local name = queryParams['filter[where][name]']
  name = name == nil and queryParams['title'] or name
  -- missing or invalid query parameters
  if (basePath == nil and name == nil) then
    return nil
  end
  -- filter tenants
  local apiList = {}
  for k, v in pairs(apis) do
    if k%2 == 0 then
      local api = cjson.decode(v)
      if (basePath ~= nil and name == nil and api.basePath == basePath) or
          (name ~= nil and basePath == nil and api.name == name) or
          (basePath ~= nil and name ~= nil and api.basePath == basePath and api.name == name) then
        apiList[#apiList+1] = api
      end
    end
  end
  return apiList
end

return _M
