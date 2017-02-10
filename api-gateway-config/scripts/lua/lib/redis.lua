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

--- @module redis
-- Module that the gateway uses to interact with redis

local cjson = require "cjson"
local utils = require "lib/utils"
local logger = require "lib/logger"
local request = require "lib/request"

local REDIS_FIELD = "resources"

local _M = {}

----------------------------
-- Initialization/Cleanup --
----------------------------

--- Initialize and connect to Redis
-- @param host redis host
-- @param port redis port
-- @param password redis password (nil if no password)
-- @param timeout redis timeout in milliseconds
function _M.init(host, port, password, timeout)
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(timeout)
  -- Connect to Redis server
  local retryCount = 4
  local connect, err = red:connect(host, port)
  while not connect and retryCount > 0 do
    local msg = utils.concatStrings({"Failed to conect to redis at ", host, ":", port, ". Retrying ", retryCount, " more times."})
    if retryCount == 1 then
      msg = utils.concatStrings({msg:sub(1, -3), "."})
    end
    logger.info(msg)
    retryCount = retryCount - 1
    os.execute("sleep 1")
    connect, err = red:connect(host, port)
  end
  if not connect then
    request.err(500, utils.concatStrings({"Failed to connect to redis: ", err}))
  end
  -- Authenticate with Redis
  if password ~= nil and password ~= "" then
    local res, err = red:auth(password)
    if not res then
      request.err(500, utils.concatStrings({"Failed to authenticate: ", err}))
    end
  end
  return red
end

--- Add current redis connection in the ngx_lua cosocket connection pool
-- @param red Redis client instance
function _M.close(red)
  -- put it into the connection pool of size 100, with 10 seconds max idle time
  local ok, err = red:set_keepalive(10000, 100)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to set keepalive: ", err}))  
  end
end

---------------------------
----------- APIs ----------
---------------------------

--- Add API to redis
-- @param red Redis client instance
-- @param id id of API
-- @param apiObj the api to add
-- @param existingAPI existing api to update
function _M.addAPI(red, id, apiObj, existingAPI)
  if existingAPI == nil then
    local apis = _M.getAllAPIs(red)
    -- Return error if api with basepath already exists
    for apiId, obj in pairs(apis) do
      if apiId%2 == 0 then
        obj = cjson.decode(obj)
        if obj.tenantId == apiObj.tenantId and obj.basePath == apiObj.basePath then
          request.err(500, "basePath not unique for given tenant.")
        end
      end
    end
  else
    -- Delete all resources for the existingAPI
    local basePath = existingAPI.basePath:sub(2)
    for path, v in pairs(existingAPI.resources) do
      local gatewayPath = ngx.unescape_uri(utils.concatStrings({basePath, ngx.escape_uri(path)}))
      gatewayPath = gatewayPath:sub(1,1) == "/" and gatewayPath:sub(2) or gatewayPath
      local redisKey = utils.concatStrings({"resources:", existingAPI.tenantId, ":", gatewayPath})
      _M.deleteResource(red, redisKey, REDIS_FIELD)
    end
  end
  -- Add new API
  apiObj = cjson.encode(apiObj):gsub("\\", "")
  local ok, err = red:hset("apis", id, apiObj)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to save the API: ", err}))
  end
  return apiObj
end

--- Get all APIs from redis
-- @param red Redis client instance
function _M.getAllAPIs(red)
  local res, err = red:hgetall("apis")
  if not res then
    request.err(500, utils.concatStrings({"Failed to retrieve APIs: ", err}))
  end
  return res
end

--- Get a single API from redis given its id
-- @param red Redis client instance
-- @param id id of API to get
function _M.getAPI(red, id)
  local api, err = red:hget("apis", id)
  if not api then
    request.err(500, utils.concatStrings({"Failed to retrieve the API: ", err}))
  end
  if api == ngx.null then
    return nil
  end
  return cjson.decode(api)
end

--- Delete an API from redis given its id
-- @param red Redis client instance
-- @param id id of API to delete
function _M.deleteAPI(red, id)
  local ok, err = red:hdel("apis", id)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete the API: ", err}))
  end
end

-----------------------------
--------- Resources ---------
-----------------------------

--- Generate Redis object for resource
-- @param ops list of operations for a given resource
-- @param apiId resource api id (nil if no api)
function _M.generateResourceObj(ops, apiId)
  local resourceObj = {
    operations = {}
  }
  for op, v in pairs(ops) do
    op = op:upper()
    resourceObj.operations[op] = {
      backendUrl = v.backendUrl,
      backendMethod = v.backendMethod
    }
    if v.policies then
      resourceObj.operations[op].policies = v.policies
    end
    if v.security then
      resourceObj.operations[op].security = v.security
    end
  end
  if apiId then
    resourceObj.apiId = apiId
  end
  return cjson.encode(resourceObj)
end

--- Create/update resource in redis
-- @param red redis client instance
-- @param key redis resource key
-- @param field redis resource field
-- @param resourceObj redis object containing operations for resource
function _M.createResource(red, key, field, resourceObj)
  -- Add/update resource to redis
  local ok, err = red:hset(key, field, resourceObj)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to save the resource: ", err}))
  end
end

--- Get resource in redis
-- @param red redis client instance
-- @param key redis resource key
-- @param field redis resource field
-- @return resourceObj redis object containing operations for resource
function _M.getResource(red, key, field)
  local resourceObj, err = red:hget(key, field)
  if not resourceObj then
    request.err(500, utils.concatStrings({"Failed to retrieve the resource: ", err}))
  end
  -- return nil if resource doesn't exist
  if resourceObj == ngx.null then
    return nil
  end
  return resourceObj
end

--- Get all resource keys for a tenant in redis
-- @param red redis client instance
-- @param tenantId tenant id
function _M.getAllResourceKeys(red, tenantId)
  -- Find all resourceKeys in redis
  local resources, err = red:scan(0, "match", utils.concatStrings({"resources:", tenantId, ":*"}), "count", 10000)
  if not resources then
    request.err(500, util.concatStrings({"Failed to retrieve resource keys: ", err}))
  end
  local cursor = resources[1]
  local resourceKeys = resources[2]
  while cursor ~= "0" do
    resources, err = red:scan(cursor, "match", utils.concatStrings({"resources:", tenantId, ":*"}), "count", 10000)
    if not resources then
      request.err(500, util.concatStrings({"Failed to retrieve resource keys: ", err}))
    end
    cursor = resources[1]
    for k, v in pairs(resources[2]) do
      resourceKeys[#resourceKeys + 1] = v
    end
  end
  return resourceKeys
end

--- Delete resource in redis
-- @param red redis client instance
-- @param key redis resource key
-- @param field redis resource field
function _M.deleteResource(red, key, field)
  local resourceObj, err = red:hget(key, field)
  if not resourceObj then
    request.err(500, utils.concatStrings({"Failed to delete the resource: ", err}))
  end
  if resourceObj == ngx.null then
    request.err(404, "Resource doesn't exist.")
  end
  -- Delete redis resource
  local ok, err = red:del(key)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete the resource: ", err}))
  else
    return ok
  end
end

-----------------------------
---------- Tenants ----------
-----------------------------

--- Add tenant to redis
-- @param red Redis client instance
-- @param id id of tenant
-- @param tenantObj the tenant to add
function _M.addTenant(red, id, tenantObj)
  local tenants = _M.getAllTenants(red)
  -- Return tenant from redis if it already exists
  for tenantId, obj in pairs(tenants) do
    if tenantId%2 == 0 then
      obj = cjson.decode(obj)
      if obj.namespace == tenantObj.namespace and obj.instance == tenantObj.instance then
        return cjson.encode(obj)
      end
    end
  end
  -- Add new tenant
  tenantObj = cjson.encode(tenantObj)
  local ok, err = red:hset("tenants", id, tenantObj)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to add the tenant: ", err}))
  end
  return tenantObj
end

--- Get all tenants from redis
-- @param red Redis client instance
function _M.getAllTenants(red)
  local res, err = red:hgetall("tenants")
  if not res then
    request.err(500, utils.concatStrings({"Failed to retrieve tenants: ", err}))
  end
  return res
end

--- Get a single tenant from redis given its id
-- @param red Redis client instance
-- @param id id of tenant to get
function _M.getTenant(red, id)
  local tenant, err = red:hget("tenants", id)
  if not tenant then
    request.err(500, utils.concatStrings({"Failed to retrieve the tenant: ", err}))
  end
  if tenant == ngx.null then
    return nil
  end
  return cjson.decode(tenant)
end

--- Delete an tenant from redis given its id
-- @param red Redis client instance
-- @param id id of tenant to delete
function _M.deleteTenant(red, id)
  local ok, err = red:hdel("tenants", id)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete the tenant: ", err}))
  end
end

-----------------------------
--- API Key Subscriptions ---
-----------------------------

--- Create/update subscription/apikey in redis
-- @param red redis client instance
-- @param key redis subscription key to create
function _M.createSubscription(red, key)
  -- Add/update a subscription key to redis
  local ok, err = red:set(key, '')
  if not ok then
    request.err(500, utils.concatStrings({"Failed to add the subscription key", err}))
  end
end

--- Delete subscription/apikey int redis
-- @param red redis client instance
-- @param key redis subscription key to delete
function _M.deleteSubscription(red, key)
  local subscription, err = red:get(key)
  if not subscription then
    request.err(500, utils.concatStrings({"Failed to delete the subscription key: ", err}))
  end
  if subscription == ngx.null then
    request.err(404, "Subscription doesn't exist.")
  end
  local ok, err = red:del(key)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete the subscription key: ", err}))
  end
end

--- Check health of gateway
function _M.healthCheck()
  request.success(200,  "Status: Gateway ready.")
end

return _M