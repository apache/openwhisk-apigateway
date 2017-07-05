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
local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"
local tenants = require "management/lib/tenants"
local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {};

--- Request handler for routing tenant calls appropriately
function _M.requestHandler()
  local requestMethod = ngx.req.get_method()
  ngx.header.content_type = "application/json; charset=utf-8"
  if requestMethod == "GET" then
    getTenants()
  elseif requestMethod == "PUT" or requestMethod == "POST" then
    addTenant()
  elseif requestMethod == "DELETE" then
    deleteTenant()
  else
    request.err(400, "Invalid verb.")
  end
end

function addTenant()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  -- Check for tenant id and use existingTenant if it already exists in redis
  local existingTenant = checkForExistingTenant(red)
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    redis.close(red)
    request.err(400, "Missing request body")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Check for tenant id in JSON body
  if existingTenant == nil and decoded.id ~= nil then
    existingTenant = redis.getTenant(red, decoded.id)
    if existingTenant == nil then
      redis.close(red)
      request.err(404, utils.concatStrings({"Unknown Tenant id ", decoded.id}))
    end
  end
  -- Error checking
  local res, err = utils.tableContainsAll(decoded, {"namespace", "instance"})
  if res == false then
    redis.close(red)
    request.err(err.statusCode, err.message)
  end
  -- Return tenant object
  local tenantObj = tenants.addTenant(red, decoded, existingTenant)
  tenantObj = cjson.encode(tenantObj)
  redis.close(red)
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
      redis.close(red)
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
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  if id == '' then
    local tenantList = tenants.getAllTenants(red, queryParams)
    tenantList = (next(tenantList) == nil) and "[]" or cjson.encode(tenantList)
    redis.close(red)
    request.success(200, tenantList)
  else
    local query = ngx.var.query
    if query ~= '' then
      if query ~= "apis" then
        redis.close(red)
        request.err(400, "Invalid request")
      else
        local apiList = tenants.getTenantAPIs(red, id, queryParams)
        apiList = (next(apiList) == nil) and "[]" or cjson.encode(apiList)
        redis.close(red)
        request.success(200, apiList)
      end
    else
      local tenant = tenants.getTenant(red, id)
      tenant = cjson.encode(tenant)
      redis.close(red)
      request.success(200, tenant)
    end
  end
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
    redis.close(red)
    request.err(404, utils.concatStrings({"Unknown tenant id ", id}))
  end
  tenants.deleteTenant(red, id)
  redis.close(red)
  request.success(200, cjson.encode({}))
end

return _M
