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
local tenants = require "management/lib/tenants"
local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {};

--- Request handler for routing tenant calls appropriately
function _M.requestHandler(dataStore)
  local requestMethod = ngx.req.get_method()
  ngx.header.content_type = "application/json; charset=utf-8"
  if requestMethod == "GET" then
    getTenants(dataStore)
  elseif requestMethod == "PUT" or requestMethod == "POST" then
    addTenant(dataStore)
  elseif requestMethod == "DELETE" then
    deleteTenant(dataStore)
  else
    request.err(400, "Invalid verb.")
  end
end

function addTenant(dataStore)
  -- Open connection to redis or use one from connection pool
  -- Check for tenant id and use existingTenant if it already exists in redis
  local existingTenant = checkForExistingTenant(dataStore)
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    dataStore:close()
    request.err(400, "Missing request body")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Check for tenant id in JSON body
  if existingTenant == nil and decoded.id ~= nil then
    existingTenant = dataStore:getTenant(decoded.id)
    if existingTenant == nil then
      request.err(404, utils.concatStrings({"Unknown Tenant id ", decoded.id}))
    end
  end
  -- Error checking
  local res, err = utils.tableContainsAll(decoded, {"namespace", "instance"})
  if res == false then
    dataStore:close()
    request.err(err.statusCode, err.message)
  end
  -- Return tenant object
  local tenantObj = tenants.addTenant(dataStore, decoded, existingTenant)
  tenantObj = cjson.encode(tenantObj)
  request.success(200, tenantObj)
end

--- Check for tenant id from uri and use existing tenant if it already exists in redis
-- @param red Redis client instance
function checkForExistingTenant(dataStore)
  local id = ngx.var.tenant_id
  local existing
  -- Get object from redis
  if id ~= nil and id ~= '' then
    existing = dataStore:getTenant(id)
    if existing == nil then
      dataStore:close()
      request.err(404, utils.concatStrings({"Unknown Tenant id ", id}))
    end
  end
  return existing
end

--- Get one or all tenants from the gateway
-- GET /v1/tenants
function getTenants(dataStore)
  local queryParams = ngx.req.get_uri_args()
  local id = ngx.var.tenant_id
  if id == '' then
    local tenantList = tenants.getAllTenants(dataStore, queryParams)
    tenantList = (next(tenantList) == nil) and "[]" or cjson.encode(tenantList)
    dataStore:close()
    request.success(200, tenantList)
  else
    local query = ngx.var.query
    if query ~= '' then
      if query ~= "apis" then
        dataStore:close()
        request.err(400, "Invalid request")
      else
        local apiList = tenants.getTenantAPIs(dataStore, id, queryParams)
        apiList = (next(apiList) == nil) and "[]" or cjson.encode(apiList)
        dataStore:close()
        request.success(200, apiList)
      end
    else
      local tenant = tenants.getTenant(dataStore, id)
      tenant = cjson.encode(tenant)
      dataStore:close()
      request.success(200, tenant)
    end
  end
end

--- Delete tenant from gateway
-- DELETE /v1/tenants/<id>
function deleteTenant(dataStore)
  local id = ngx.var.tenant_id
  if id == nil or id == '' then
    request.err(400, "No id specified.")
  end
  local tenant = dataStore:getTenant(id)
  if tenant == nil then
    dataStore:close()
    request.err(404, utils.concatStrings({"Unknown tenant id ", id}))
  end
  tenants.deleteTenant(dataStore, id)
  request.success(200, cjson.encode({}))
end

return _M
