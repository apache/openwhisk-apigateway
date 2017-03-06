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

--- Request handler for routing tenant calls appropriately
function _M.requestHandler()
  local requestMethod = ngx.req.get_method()
  if requestMethod == "GET" then
    getTenants()
  elseif requestMethod == "PUT" then
    addTenant()
  elseif requestMethod == "POST" then
    addTenant()
  elseif requestMethod == "DELETE" then
    deleteTenant()
  else
    ngx.status = 400
    ngx.say("Invalid verb")
  end
end

--- Add a tenant to the Gateway
-- PUT /v1/tenants
-- body:
-- {
--    "namespace": *(String) tenant namespace
--    "instance": *(String) tenant instance
-- }
function addTenant()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  -- Check for tenant id and use existingTenant if it already exists in redis
  local existingTenant = checkForExistingTenant(red)
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
  local res, err = utils.tableContainsAll(decoded, {"namespace", "instance"})
  if res == false then
    request.err(err.statusCode, err.message)
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
function checkForExistingTenant(red)
  local id = ngx.var.tenant_id
  local existing
  -- Get object from redis
  if id ~= nil and id ~= '' then
    existing = redis.getTenant(red, id)
    if existing == nil then
      request.err(404, utils.concatStrings({"Unknown Tenant id ", id}))
    end
  end
  return existing
end

--- Get one or all tenants from the gateway
-- GET /v1/tenants
function getTenants()
  local queryParams = ngx.req.get_uri_args()
  local id = ngx.var.tenant_id
  if id == nil or id == '' then
    getAllTenants(queryParams)
  else
    local query = ngx.var.query
    if (query ~= nil and query ~= '') then
      if query ~= "apis" then
        request.err(400, "Invalid request")
      else
        getTenantAPIs(id, queryParams)
      end
    else
      getTenant(id)
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
  end
  ngx.header.content_type = "application/json; charset=utf-8"
  tenantList = (next(tenantList) == nil) and "[]" or cjson.encode(tenantList)
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
  return tenantList
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
  end
  ngx.header.content_type = "application/json; charset=utf-8"
  apiList = (next(apiList) == nil) and "[]" or cjson.encode(apiList)
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
  return apiList
end

--- Delete tenant from gateway
-- DELETE /v1/tenants/<id>
function deleteTenant()
  local id = ngx.var.tenant_id
  if id == nil or id == '' then
    request.err(400, "No id specified.")
  end
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local tenant = redis.getTenant(red, id)
  if tenant == nil then
    request.err(404, utils.concatStrings({"Unknown tenant id ", id}))
  end
  redis.deleteTenant(red, id)
  redis.close(red)
  request.success(200, {})
end

return _M
