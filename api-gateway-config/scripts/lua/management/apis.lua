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
local resources = require "management/resources"

local MANAGEDURL_HOST = os.getenv("PUBLIC_MANAGEDURL_HOST")
MANAGEDURL_HOST = (MANAGEDURL_HOST ~= nil and MANAGEDURL_HOST ~= '') and MANAGEDURL_HOST or "0.0.0.0"
local MANAGEDURL_PORT = os.getenv("PUBLIC_MANAGEDURL_PORT")
MANAGEDURL_PORT = (MANAGEDURL_PORT ~= nil and MANAGEDURL_PORT ~= '') and MANAGEDURL_PORT or "8080"
local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}

--- Add an api to the Gateway
-- PUT /v1/apis
-- body:
-- {
--    "name": *(String) name of API
--    "basePath": *(String) base path for api
--    "tenantId": *(String) tenant id
--    "resources": *(String) resources to add
-- }
function _M.addAPI()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  -- Check for api id from uri and use existingAPI if it already exists in redis
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  local existingAPI = checkURIForExistingAPI(red, uri)
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    request.err(400, "Missing request body")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Check for api id in JSON body
  if existingAPI == nil and decoded.id ~= nil then
    existingAPI = redis.getAPI(red, decoded.id)
    if existingAPI == nil then
      request.err(404, utils.concatStrings({"Unknown API id ", decoded.id}))
    end
  end
  -- Error checking
  local fields = {"name", "basePath", "tenantId", "resources"}
  for k, v in pairs(fields) do
    local res, err = isValid(red, v, decoded[v])
    if res == false then
      request.err(err.statusCode, err.message)
    end
  end
  -- Format basePath
  local basePath = decoded.basePath:sub(1,1) == '/' and decoded.basePath:sub(2) or decoded.basePath
  basePath = basePath:sub(-1) == '/' and basePath:sub(1, -2) or basePath
  -- Create managedUrl object
  local uuid = existingAPI ~= nil and existingAPI.id or utils.uuid()
  local managedUrl = utils.concatStrings({"http://", MANAGEDURL_HOST, ":", MANAGEDURL_PORT, "/api/", decoded.tenantId})
  if basePath:sub(1,1) ~= '' then
    managedUrl = utils.concatStrings({managedUrl, "/", basePath})
  end
  local managedUrlObj = {
    id = uuid,
    name = decoded.name,
    basePath = utils.concatStrings({"/", basePath}),
    tenantId = decoded.tenantId,
    resources = decoded.resources,
    managedUrl = managedUrl
  }
  -- Add API object to redis
  managedUrlObj = redis.addAPI(red, uuid, managedUrlObj, existingAPI)
  -- Add resources to redis
  for path, resource in pairs(decoded.resources) do
    local gatewayPath = utils.concatStrings({basePath, path})
    gatewayPath = (gatewayPath:sub(1,1) == '/') and gatewayPath:sub(2) or gatewayPath
    resources.addResource(red, resource, gatewayPath, decoded.tenantId)
  end
  redis.close(red)
  -- Return managed url object
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, managedUrlObj)
end

--- Check for api id from uri and use existing API if it already exists in redis
-- @param red Redis client instance
-- @param uri Uri of request. Eg. /v1/apis/{id}
function checkURIForExistingAPI(red, uri)
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
    existing = redis.getAPI(red, id)
    if existing == nil then
      request.err(404, utils.concatStrings({"Unknown API id ", id}))
    end
  end
  return existing
end

--- Check JSON body fields for errors
-- @param red Redis client instance
-- @param field name of field
-- @param object field object
function isValid(red, field, object)
  -- Check that field exists in body
  if not object then
    return false, { statusCode = 400, message = utils.concatStrings({"Missing field '", field, "' in request body."}) }
  end
  -- Additional check for basePath
  if field == "basePath" then
    local basePath = object
    if string.match(basePath, "'") then
      return false, { statusCode = 400, message = "basePath contains illegal character \"'\"." }
    end
  end
  -- Additional check for tenantId
  if field == "tenantId" then
    local tenant = redis.getTenant(red, object)
    if tenant == nil then
      return false, { statusCode = 404, message = utils.concatStrings({"Unknown tenant id ", object }) }
    end
  end
  if field == "resources" then
    local res, err = checkResources(object)
    if res ~= nil and res == false then
      return res, err
    end
  end
  -- All error checks passed
  return true
end

--- Error checking for resources
-- @param resources resources object
function checkResources(resources)
  if next(resources) == nil then
    return false, { statusCode = 400, message = "Empty resources object." }
  end
  for path, resource in pairs(resources) do
    -- Check resource path for illegal characters
    if string.match(path, "'") then
      return false, { statusCode = 400, message = "resource path contains illegal character \"'\"." }
    end
    -- Check that resource path begins with slash
    if path:sub(1,1) ~= '/' then
      return false, { statusCode = 400, message = "Resource path must begin with '/'." }
    end
    -- Check operations object
    local res, err = checkOperations(resource.operations)
    if res ~= nil and res == false then
      return res, err
    end
  end
end

--- Error checking for operations
-- @param operations operations object
function checkOperations(operations)
  if not operations or next(operations) == nil then
    return false, { statusCode = 400, message = "Missing or empty field 'operations' or in resource path object." }
  end
  local allowedVerbs = {GET=true, POST=true, PUT=true, DELETE=true, PATCH=true, HEAD=true, OPTIONS=true}
  for verb, verbObj in pairs(operations) do
    if allowedVerbs[verb:upper()] == nil then
      return false, { statusCode = 400, message = utils.concatStrings({"Resource verb '", verb, "' not supported."}) }
    end
    -- Check required fields
    local requiredFields = {"backendMethod", "backendUrl"}
    for k, v in pairs(requiredFields) do
      if verbObj[v] == nil then
        return false, { statusCode = 400, message = utils.concatStrings({"Missing field '", v, "' for '", verb, "' operation."}) }
      end
      if v == "backendMethod" then
        local backendMethod = verbObj[v]
        if allowedVerbs[backendMethod:upper()] == nil then
          return false, { statusCode = 400, message = utils.concatStrings({"backendMethod '", backendMethod, "' not supported."}) }
        end
      end
    end
    -- Check optional fields
    local res, err = checkOptionalPolicies(verbObj.policies, verbObj.security)
    if res ~= nil and res == false then
      return res, err
    end
  end
end

--- Error checking for policies and security
-- @param policies policies object
-- @param security security object
function checkOptionalPolicies(policies, security)
  if policies then
    for k, v in pairs(policies) do
      local validTypes = {reqMapping = true, rateLimit = true}
      if (v.type == nil or v.value == nil) then
        return false, { statusCode = 400, message = "Missing field in policy object. Need \"type\" and \"scope\"." }
      elseif validTypes[v.type] == nil then
        return false, { statusCode = 400, message = "Invalid type in policy object. Valid: \"reqMapping\", \"rateLimit\"" }
      end
    end
  end
  if security then
    local validScopes = {tenant=true, api=true, resource=true}
    if (security.type == nil or security.scope == nil) then
      return false, { statusCode = 400, message = "Missing field in security object. Need \"type\" and \"scope\"." }
    end
    if (security.type == "oauth" and security.provider == nil) then
      return false, { statusCode = 400, message = "Missing field in security object. Need \"provider\"."}
    end
    if (security.type == "oauth") then
      if not pcall(require, utils.concatStrings({"oauth/", security.provider})) then 
        return false, {statusCode = 400, message = "Supplied OAuth provider is not currently supported."} 
      end
    end
    if validScopes[security.scope] == nil then
      return false, { statusCode = 400, message = "Invalid scope in security object. Valid: \"tenant\", \"api\", \"resource\"." }
    end
  end
end


--- Helper function for adding a resource to redis and creating an nginx conf file
-- @param red
-- @param resource
-- @param gatewayPath
-- @param tenantId
function addResource(red, resource, gatewayPath, tenantId)
  -- Create resource object and add to redis
  local redisKey = utils.concatStrings({"resources", ":", tenantId, ":", gatewayPath})
  local apiId
  local operations
  for k, v in pairs(resource) do
    if k == 'apiId' then
      apiId = v
    elseif k == 'operations' then
      operations = v
    end
  end
  local resourceObj = redis.generateResourceObj(operations, apiId)
  redis.createResource(red, redisKey, REDIS_FIELD, resourceObj)
end

--- Get one or all APIs from the gateway
-- GET /v1/apis
function _M.getAPIs()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  local id
  local index = 1
  local tenantQuery = false
  for word in string.gmatch(uri, '([^/]+)') do
    if index == 3 then
      id = word
    elseif index == 4 then
      if word == 'tenant' then
        tenantQuery = true
      else
        request.err(400, "Invalid request")
      end
    end
    index = index + 1
  end
  if id == nil then
    getAllAPIs()
  else
    if tenantQuery == false then
      getAPI(id)
    else
      getAPITenant(id)
    end
  end
end

--- Get all APIs in redis
function getAllAPIs()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local res = redis.getAllAPIs(red)
  redis.close(red)
  local apiList = {}
  for k, v in pairs(res) do
    if k%2 == 0 then
      apiList[#apiList+1] = cjson.decode(v)
    end
  end
  apiList = cjson.encode(apiList)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, apiList)
end

--- Get API by its id
-- @param id of API
function getAPI(id)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local api = redis.getAPI(red, id)
  if api == nil then
    request.err(404, utils.concatStrings({"Unknown api id ", id}))
  end
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, cjson.encode(api))
end

--- Get belongsTo relation tenant
-- @param id id of API
function getAPITenant(id)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local api = redis.getAPI(red, id)
  if api == nil then
    request.err(404, utils.concatStrings({"Unknown api id ", id}))
  end
  local tenantId = api.tenantId
  local tenant = redis.getTenant(red, tenantId)
  if tenant == nil then
    request.err(404, utils.concatStrings({"Unknown tenant id ", tenantId}))
  end
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, cjson.encode(tenant))
end

--- Delete API from gateway
-- DELETE /v1/apis/<id>
function _M.deleteAPI()
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
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local api = redis.getAPI(red, id)
  if api == nil then
    request.err(404, utils.concatStrings({"Unknown API id ", id}))
  end
  -- Delete API
  redis.deleteAPI(red, id)
  -- Delete all resources for the API
  local basePath = api.basePath:sub(2)
  for path, v in pairs(api.resources) do
    local gatewayPath = utils.concatStrings({basePath, path})
    gatewayPath = (gatewayPath:sub(1,1) == '/') and gatewayPath:sub(2) or gatewayPath
    resources.deleteResource(red, gatewayPath, api.tenantId)
  end
  redis.close(red)
  request.success(200, {})
end

return _M;
