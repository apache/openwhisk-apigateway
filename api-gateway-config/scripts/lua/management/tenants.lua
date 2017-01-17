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
local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {};

--- Add a tenant to the Gateway
-- PUT /v1/tenants
-- body:
-- {
--    "namespace": *(String) tenant namespace
--    "instance": *(String) tenant instance
-- }
function _M.addTenant()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  -- Check for tenant id and use existingTenant if it already exists in redis
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  local existingTenant = checkURIForExistingTenant(red, uri)
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    request.err(400, "Missing request body")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Check for tenant id in JSON body
  if existingTenant == nil and decoded.id ~= nil then
    existingTenant = redis.getTenant(red, decoded.id)
    if existingTenant == nil then
      request.err(404, utils.concatStrings({"Unknown Tenant id ", decoded.id}))
    end
  end
  -- Error checking
  local fields = {"namespace", "instance"}
  for k, v in pairs(fields) do
    if not decoded[v] then
      request.err(400, utils.concatStrings({"Missing field '", v, "' in request body."}))
    end
  end
  -- Return tenant object
  local uuid = existingTenant ~= nil and existingTenant.id or utils.uuid()
  local tenantObj = {
    id = uuid,
    namespace = decoded.namespace,
    instance = decoded.instance
  }
  tenantObj = redis.addTenant(red, uuid, tenantObj)
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, tenantObj)
end

--- Check for tenant id from uri and use existing tenant if it already exists in redis
-- @param red Redis client instance
-- @param uri Uri of request. Eg. /v1/tenants/{id}
function checkURIForExistingTenant(red, uri)
  local id, existing
  local index = 1
  -- Check if id is in the uri
  for word in string.gmatch(uri, '([^/]+)') do
    if index == 3 then
      id = word
    end
    index = index + 1
  end
  -- Get object from redis
  if id ~= nil then
    existing = redis.getTenant(red, id)
    if existing == nil then
      request.err(404, utils.concatStrings({"Unknown Tenant id ", id}))
    end
  end
  return existing
end

--- Get one or all tenants from the gateway
-- GET /v1/tenants
function _M.getTenants()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  local queryParams = ngx.req.get_uri_args()
  local id
  local index = 1
  local apiQuery = false
  for word in string.gmatch(uri, '([^/]+)') do
    if index == 3 then
      id = word
    elseif index == 4 then
      if word:lower() == 'apis' then
        apiQuery = true
      else
        request.err(400, "Invalid request")
      end
    end
    index = index + 1
  end
  if id == nil then
    getAllTenants(queryParams)
  else
    if apiQuery == false then
      getTenant(id)
    else
      getTenantAPIs(id, queryParams)
    end
  end
end

--- Get all tenants in redis
-- @param queryParams object containing optional query parameters
function getAllTenants(queryParams)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local tenants = redis.getAllTenants(red)
  redis.close(red)
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
    tenantList = cjson.encode(tenantList)
  end
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, tenantList)
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
  return cjson.encode(tenantList)
end

--- Get tenant by its id
-- @param id tenant id
function getTenant(id)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local tenant = redis.getTenant(red, id)
  if tenant == nil then
    request.err(404, utils.concatStrings({"Unknown tenant id ", id }))
  end
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, cjson.encode(tenant))
end

--- Get APIs associated with tenant
-- @param id tenant id
-- @param queryParams object containing optional query parameters
function getTenantAPIs(id, queryParams)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local apis = redis.getAllAPIs(red)
  redis.close(red)
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
    apiList = cjson.encode(apiList)
  end
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, apiList)
end

--- Filter apis based on query paramters
-- @param queryParams query parameters to filter apis
function filterTenantAPIs(id, apis, queryParams)
  local basePath = queryParams['filter[where][basePath]']
  local name = queryParams['filter[where][name]']
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
  return cjson.encode(apiList)
end

--- Delete tenant from gateway
-- DELETE /v1/tenants/<id>
function _M.deleteTenant()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  local index = 1
  local id
  for word in string.gmatch(uri, '([^/]+)') do
    if index == 3 then
      id = word
    end
    index = index + 1
  end
  if id == nil then
    request.err(400, "No id specified.")
  end
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.deleteTenant(red, id)
  redis.close(red)
  request.success(200, {})
end

return _M