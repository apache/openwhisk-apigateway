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
local filemgmt = require "lib/filemgmt"
local utils = require "lib/utils"
local logger = require "lib/logger"
local request = require "lib/request"
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
-- PUT http://0.0.0.0:9000/APIs
-- body:
-- {
--    "name": *(String) name of API
--    "basePath": *(String) base path for api
--    "tenantId": *(String) tenant id
--    "resources": *(String) resources to add
-- }
function _M.addAPI()
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    request.err(400, "Missing request body")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Error checking
  local fields = {"name", "basePath", "tenantId", "resources"}
  for k, v in pairs(fields) do
    local res, err = isValid(v, decoded[v])
    if res == false then
      request.err(err.statusCode, err.message)
    end
  end
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  -- Format basePath
  local basePath = decoded.basePath:sub(1,1) == '/' and decoded.basePath:sub(2) or decoded.basePath
  -- Add resources to redis and create nginx conf files
  for path, resource in pairs(decoded.resources) do
    local gatewayPath = utils.concatStrings({basePath, ngx.escape_uri(path)})
    addResource(red, resource, gatewayPath, decoded.tenantId)
  end
  -- Generate random uuid for api
  local uuid = utils.uuid()
  -- Create managed url object
  local managedUrlObj = {
    id = uuid,
    name = decoded.name,
    basePath = utils.concatStrings({"/", basePath}),
    tenantId = decoded.tenantId,
    resources = decoded.resources,
    managedUrl = utils.concatStrings({"http://0.0.0.0:8080/api/", decoded.tenantId, "/", basePath})
  }
  managedUrlObj = cjson.encode(managedUrlObj):gsub("\\", "")
  -- Add API object to redis
  redis.addAPI(red, uuid, managedUrlObj)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  -- Return managed url object
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, managedUrlObj)
end

--- Check JSON body fields for errors
-- @param field name of field
-- @param object field object
function isValid(field, object)
  -- Check that field exists in body
  if not object then
    return false, { statusCode = 400, message = utils.concatStrings({"Missing field '", field, "' in request body."}) }
  end
  -- Additional checks for resource object
  if field == "resources" then
    local resources = object
    if next(object) == nil then
      return false, { statusCode = 400, message = "Empty resources object." }
    end
    for path, resource in pairs(resources) do
      -- Check that resource path begins with slash
      if path:sub(1,1) ~= '/' then
        return false, { statusCode = 400, message = "Resource path must begin with '/'." }
      end
      -- Check operations object
      if not resource.operations or next(resource.operations) == nil then
        return false, { statusCode = 400, message = "Missing or empty field 'operations' or in resource path object." }
      end
      for verb, verbObj in pairs(resource.operations) do
        local allowedVerbs = {GET=true, POST=true, PUT=true, DELETE=true, PATCH=true, HEAD=true, OPTIONS=true}
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
        local policies = verbObj.policies
        if policies then
          for k, v in pairs(policies) do
            if v.type == nil then
              return false, { statusCode = 400, message = "Missing field 'type' in policy object." }
            end
          end
        end
        local security = verbObj.security
        if security and security.type == nil then
          return false, { statusCode = 400, message = "Missing field 'type' in security object." }
        end
      end
    end
  end
  -- All error checks passed
  return true
end

--- Helper function for adding a resource to redis and creating an nginx conf file
-- @param red
-- @param resource
-- @param gatewayPath
-- @param tenantId
function addResource(red, resource, gatewayPath, tenantId)
  -- Create resource object and add to redis
  local redisKey = utils.concatStrings({"resources", ":", tenantId, ":", ngx.unescape_uri(gatewayPath)})
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
  filemgmt.createResourceConf(BASE_CONF_DIR, tenantId, gatewayPath, resourceObj)
end

--- Get one or all APIs from the gateway
-- PUT http://0.0.0.0:9000/APIs
function _M.getAPIs()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  if uri:len() <= 6 then
    getAllAPIs()
  else
    local id = uri:sub(7)
    getAPI(id)
  end
end

--- Get all APIs in redis
function getAllAPIs()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
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
-- @param id
function getAPI(id)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local api = redis.getAPI(red, id)
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, cjson.encode(api))
end

--- Delete API from gateway
-- DELETE http://0.0.0.0:9000/APIs/<id>
function _M.deleteAPI()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  if uri:len() <= 6 then
    request.err(400, "No id specified.")
  end
  local id = uri:sub(7)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local api = redis.getAPI(red, id)
  -- Delete all resources for the API
  local basePath = api.basePath:sub(2)
  for path, v in pairs(api.resources) do
    local gatewayPath = utils.concatStrings({basePath, ngx.escape_uri(path)})
    deleteResource(red, gatewayPath, api.tenantId)
  end
  redis.deleteAPI(red, id)
  redis.close(red)
  request.success(200, {})
end

--- Helper function for deleting resource in redis and appropriate conf files
-- @param red redis instance
-- @param gatewayPath path in gateway
-- @param tenantId tenant id
function deleteResource(red, gatewayPath, tenantId)
  local redisKey = utils.concatStrings({"resources:", tenantId, ":", ngx.unescape_uri(gatewayPath)})
  redis.deleteResource(red, redisKey, REDIS_FIELD)
  filemgmt.deleteResourceConf(BASE_CONF_DIR, tenantId, gatewayPath)
end

-----------------------------
---------- Tenants ----------
-----------------------------

--- Add a tenant to the Gateway
-- PUT http://0.0.0.0:9000/Tenants
-- body:
-- {
--    "namespace": *(String) tenant namespace
--    "instance": *(String) tenant instance
-- }
function _M.addTenant()
  -- Read in the PUT JSON Body
  ngx.req.read_body()
  local args = ngx.req.get_body_data()
  if not args then
    request.err(400, "Missing request body")
  end
  -- Convert json into Lua table
  local decoded = cjson.decode(args)
  -- Error checking
  local fields = {"namespace", "instance"}
  for k, v in pairs(fields) do
    if not decoded[v] then
      request.err(400, utils.concatStrings({"Missing field '", v, "' in request body."}))
    end
  end
  -- Generate random uuid for tenant
  local uuid = utils.uuid()
  local tenantObj = {
    id = uuid,
    namespace = decoded.namespace,
    instance = decoded.instance
  }
  tenantObj = cjson.encode(tenantObj)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.addTenant(red, uuid, tenantObj)
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, tenantObj)
end

--- Get one or all tenants from the gateway
-- PUT http://0.0.0.0:9000/Tenants
function _M.getTenants()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  if uri:len() <= 9 then
    getAllTenants()
  else
    local id = uri:sub(10)
    getTenant(id)
  end
end

--- Get all tenants in redis
function getAllTenants()
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
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
-- @param id
function getTenant(id)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local tenant = redis.getTenant(red, id)
  redis.close(red)
  ngx.header.content_type = "application/json; charset=utf-8"
  request.success(200, cjson.encode(tenant))
end

--- Delete tenant from gateway
-- DELETE http://0.0.0.0:9000/Tenants/<id>
function _M.deleteTenant()
  local uri = string.gsub(ngx.var.request_uri, "?.*", "")
  if uri:len() <= 9 then
    request.err(400, "No id specified.")
  end
  local id = uri:sub(10)
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.deleteTenant(red, id)
  redis.close(red)
  request.success(200, {})
end

------------------------------
----- Pub/Sub with Redis -----
------------------------------

--- Subscribe to redis
-- GET http://0.0.0.0:9000/subscribe
function _M.subscribe()
  -- Initialize and connect to redis
  local redisGetClient = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local redisSubClient = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 60000) -- read_reply will timeout every minute
  logger.debug(utils.concatStrings({"\nConnected to redis at ", REDIS_HOST, ":", REDIS_PORT}))
  redis.subscribe(redisSubClient, redisGetClient)
  ngx.exit(200)
end

--- Unsusbscribe to redis
-- GET http://0.0.0.0:9000/unsubscribe
function _M.unsubscribe()
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.unsubscribe(red)
  request.success(200, "Unsubscribed to redis")
end

--- Add an apikey/subscription to redis
-- PUT http://0.0.0.0:9000/subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenant: *(String) tenant id
--    resource: (String) url-encoded resource path
--    api: (String) api id
-- }
function _M.addSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  redis.createSubscription(red, redisKey)
  -- Add current redis connection in the ngx_lua cosocket connection pool
  redis.close(red)
  request.success(200, "Subscription created.")
end

---------------------------
------ Subscriptions ------
---------------------------

--- Delete apikey/subscription from redis
-- DELETE http://0.0.0.0:9000/subscriptions
-- Body:
-- {
--    key: *(String) key for tenant/api/resource
--    scope: *(String) tenant or api or resource
--    tenant: *(String) tenant id
--    resource: (String) url-encoded resource path
--    api: (String) api id
-- }
function _M.deleteSubscription()
  -- Validate body and create redisKey
  local redisKey = validateSubscriptionBody()
  -- Initialize and connect to redis
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
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
  local args = ngx.req.get_post_args()
  if not args then
    request.err(400, "Missing request body.")
  end
  -- Convert json into Lua table
  local decoded
  if next(args) then
    decoded = utils.convertJSONBody(args)
  else
    request.err(400, "Request body required.")
  end
  -- Check required fields
  local requiredFieldList = {"key", "scope", "tenant"}
  for i, field in ipairs(requiredFieldList) do
    if not decoded[field] then
      request.err(400, utils.concatStrings({"\"", field, "\" missing from request body."}))
    end
  end
  -- Check if we're using tenant or resource or api
  local resource = decoded.resource
  local apiId = decoded.apiId
  local redisKey
  local prefix = utils.concatStrings({"subscriptions:tenant:", decoded.tenant})
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
