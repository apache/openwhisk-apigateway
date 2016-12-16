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

--- @module management
-- Defines and exposes a lightweight API management to create and remove resources in the running API Gateway
-- @author Alex Song (songs)

local cjson = require "cjson"
local redis = require "lib/redis"
local utils = require "lib/utils"
local logger = require "lib/logger"
local request = require "lib/request"
local MANAGEDURL_HOST = os.getenv("PUBLIC_MANAGEDURL_HOST")
MANAGEDURL_HOST = (MANAGEDURL_HOST ~= nil and MANAGEDURL_HOST ~= '') and MANAGEDURL_HOST or "0.0.0.0"
local MANAGEDURL_PORT = os.getenv("PUBLIC_MANAGEDURL_PORT")
MANAGEDURL_PORT = (MANAGEDURL_PORT ~= nil and MANAGEDURL_PORT ~= '') and MANAGEDURL_PORT or "8080"
local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")
local REDIS_FIELD = "resources"
local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local _M = {}

--------------------------
---------- APIs ----------
--------------------------

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
  local existingAPI = checkURIForExisting(red, uri, "api")
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
    addResource(red, resource, gatewayPath, decoded.tenantId)
  end
  redis.close(red)
  -- Return managed url object
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, managedUrlObj)
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
    elseif validScopes[security.scope] == nil then
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
    deleteResource(red, gatewayPath, api.tenantId)
  end
  redis.close(red)
  request.success(200, {})
end

--- Helper function for deleting resource in redis and appropriate conf files
-- @param red redis instance
-- @param gatewayPath path in gateway
-- @param tenantId tenant id
function deleteResource(red, gatewayPath, tenantId)
  local redisKey = utils.concatStrings({"resources:", tenantId, ":", gatewayPath})
  redis.deleteResource(red, redisKey, REDIS_FIELD)
end

-----------------------------
---------- Tenants ----------
-----------------------------

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
  local existingTenant = checkURIForExisting(red, uri, "tenant")
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

--- Get one or all tenants from the gateway
-- GET /v1/tenants
function _M.getTenants()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
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
    getAllTenants()
  else
    if apiQuery == false then
      getTenant(id)
    else
      getTenantAPIs(id)
    end
  end
end

--- Get all tenants in redis
function getAllTenants()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local res = redis.getAllTenants(red)
  redis.close(red)
  local tenantList = {}
  for k, v in pairs(res) do
    if k%2 == 0 then
      tenantList[#tenantList+1] = cjson.decode(v)
    end
  end
  tenantList = cjson.encode(tenantList)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, tenantList)
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
function getTenantAPIs(id)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  local res = redis.getAllAPIs(red)
  redis.close(red)
  local apiList = {}
  for k, v in pairs(res) do
    if k%2 == 0 then
      local decoded = cjson.decode(v)
      if decoded.tenantId == id then
        apiList[#apiList+1] = decoded
      end
    end
  end
  apiList = cjson.encode(apiList)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, apiList)
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

------------------------------
----- Pub/Sub with Redis -----
------------------------------

--- Subscribe to redis
-- GET /v1/subscribe
function _M.subscribe()
  redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS)
  logger.info(utils.concatStrings({"Connected to redis at ", REDIS_HOST, ":", REDIS_PORT}))
  while true do end
  ngx.exit(200)
end

----------------------------
------- Health Check -------
----------------------------

--- Check health of gateway
function _M.healthCheck()
  redis.healthCheck()
end

---------------------------
------ Subscriptions ------
---------------------------

--- Add an apikey/subscription to redis
-- PUT /subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenantId: *(String) tenant id
--    resource: (String) url-encoded resource path
--    apiId: (String) api id
-- }
function _M.addSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  redis.createSubscription(red, redisKey)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  request.success(200, "Subscription created.")
end

--- Delete apikey/subscription from redis
-- DELETE /subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenantId: *(String) tenant id
--    resource: (String) url-encoded resource path
--    apiId: (String) api id
-- }
function _M.deleteSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 10000)
  -- Return if subscription doesn't exist
  redis.deleteSubscription(red, redisKey)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  request.success(200, "Subscription deleted.")
end

--- Check the request JSON body for correct fields
-- @return redisKey subscription key for redis
function validateSubscriptionBody()
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    request.err(400, "Missing request body.")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Check required fields
  local requiredFieldList = {"key", "scope", "tenantId"}
  for i, field in ipairs(requiredFieldList) do
    if not decoded[field] then
      request.err(400, utils.concatStrings({"\"", field, "\" missing from request body."}))
    end
  end
  -- Check if we're using tenant or resource or api
  local resource = decoded.resource
  local apiId = decoded.apiId
  local redisKey
  local prefix = utils.concatStrings({"subscriptions:tenant:", decoded.tenantId})
  if decoded.scope == "tenant" then
    redisKey = prefix
  elseif decoded.scope == "resource" then
    if resource ~= nil then
      redisKey = utils.concatStrings({prefix, ":resource:", resource})
    else
      request.err(400, "\"resource\" missing from request body.")
    end
  elseif decoded.scope == "api" then
    if apiId ~= nil then
      redisKey = utils.concatStrings({prefix, ":api:", apiId})
    else
      request.err(400, "\"apiId\" missing from request body.")
    end
  else 
    request.err(400, "Invalid scope")
  end
  redisKey = utils.concatStrings({redisKey, ":key:", decoded.key})
  return redisKey
end


--- Check for api id from uri and use existingAPI if it already exists in redis
-- @param red Redis client instance
-- @param uri Uri of request. Eg. /v1/apis/{id}
-- @param type type to look for in redis. "api" or "tenant"
function checkURIForExisting(red, uri, type)
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
    if type == "api" then
      existing = redis.getAPI(red, id)
      if existing == nil then
        request.err(404, utils.concatStrings({"Unknown API id ", id}))
      end
    elseif type == "tenant" then
      existing = redis.getTenant(red, id)
      if existing == nil then
        request.err(404, utils.concatStrings({"Unknown Tenant id ", id}))
      end
    end
  end
  return existing
end

--- Parse the request uri to get the redisKey, tenant, and gatewayPath
-- @param requestURI String containing the uri in the form of "/resources/<tenant>/<path>"
-- @return list containing redisKey, tenant, gatewayPath
function parseRequestURI(requestURI)
  local list = {}
  for i in string.gmatch(requestURI, '([^/]+)') do
    list[#list + 1] = i
  end
  if not list[1] or not list[2] then
    request.err(400, "Request path should be \"/resources/<tenant>/<url-encoded-resource>\"")
  end

  return list  --prefix, tenant, gatewayPath, apiKey
end

return _M
