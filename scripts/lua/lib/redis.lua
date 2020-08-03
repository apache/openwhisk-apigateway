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

--- @module redis
-- Module that the gateway uses to interact with redis

local cjson = require "cjson"
local utils = require "lib/utils"
local logger = require "lib/logger"
local request = require "lib/request"
local lrucache
local CACHE_SIZE
local CACHE_TTL
local c

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")
local REDIS_TIMEOUT = os.getenv("REDIS_TIMEOUT")
if REDIS_TIMEOUT == nil then
  REDIS_TIMEOUT = 10000
else
  REDIS_TIMEOUT = tonumber(REDIS_TIMEOUT)
end
local CACHING_ENABLED = os.getenv('CACHING_ENABLED')
if CACHING_ENABLED then
  lrucache = require "resty.lrucache"
  CACHE_SIZE = tonumber(os.getenv('CACHE_SIZE'))
  CACHE_TTL = tonumber(os.getenv('CACHE_TTL'))
  local err_c
  c, err_c = lrucache.new(CACHE_SIZE)
  if not c then
    return error("Failed to initialize LRU cache" .. (err_c or "unknown"))
  end
end


local REDIS_RETRY_COUNT = os.getenv('REDIS_RETRY_COUNT')
REDIS_RETRY_COUNT = REDIS_RETRY_COUNT == nil and 3 or tonumber(REDIS_RETRY_COUNT)
local REDIS_FIELD = "resources"

local _M = {}

----------------------------
-- Initialization/Cleanup --
----------------------------

--- Initialize and connect to Redis
function _M.init()
  local host = REDIS_HOST
  local password = REDIS_PASS
  local port = REDIS_PORT
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(REDIS_TIMEOUT)
  -- Connect to Redis server
  local retryCount = REDIS_RETRY_COUNT
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
  if password ~= nil and password ~= "" and red:get_reused_times() < 1 then
    local res, err_auth = red:auth(password)
    if not res then
      ngx.log(ngx.ERR, utils.concatStrings({"[redis] failed to authenticate: ", err_auth}))
      request.err(500, "Internal server error")
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
    ngx.log(ngx.ERR, utils.concatStrings({"Failed to set keepalive: ", err}))
    request.err(500, "Internal server error")
  end
end

-- LRU Caching methods

--- Call function with retry logic
-- @param func function to call
-- @param args arguments to pass in to function
local function call(func, args)
  local res, err = func(unpack(args))
  local retryCount = REDIS_RETRY_COUNT
  while not res and retryCount > 0 do
    res, err = func(unpack(args))
    retryCount = retryCount - 1
  end
  return res, err
end

local function exists(red, key, snapshotId)
  if snapshotId ~= nil then
    key = utils.concatStrings({'snapshots:', snapshotId, ':', key})
  end
  if CACHING_ENABLED then
    local cached = c:get(key)
    if cached ~= nil then
      return 1
    end
  -- if it isn't in the cache, try and load it in there
    if red == nil then
      red = _M.init()
    end
    local result = red:get(key)
    if result ~= ngx.null then
      c:set(key, result, CACHE_TTL)
      return 1, red
    end
    return 0
  else
    if red == nil then
      red = _M.init()
    end
    return call(red.exists, {red, key}), red
  end
end

local function get(red, key)
  if CACHING_ENABLED then
    local cached = c:get(key)
    if cached ~= nil then
      return cached
    else
      if red == nil then
        red = _M.init()
      end
      local result = red:get(key)
      c:set(key, result, CACHE_TTL)
      return result, red
    end
  else
    if red == nil then
      red = _M.init()
    end
    return call(red.get, {red, key})
  end
end

local function hget(red, key, id)
  if CACHING_ENABLED then
    local cachedmap = c:get(key)
    if cachedmap ~= nil then
      local cached = cachedmap:get(id)
      if cached ~= nil then
         return cached
      else
        if red == nil then
          red = _M.init()
        end
        local result = red:hget(key, id)
        cachedmap:set(id, result, CACHE_TTL)
        c:set(key, cachedmap, CACHE_TTL)
        return result, red
      end
    else
      if red == nil then
        red = _M.init()
      end
      local result = red:hget(key, id)
      local newcache = lrucache.new(CACHE_SIZE)
      newcache:set(id, result, CACHE_TTL)
      c:set(key, newcache, CACHE_TTL)
      return result, red
    end
  else
    if red == nil then
      red = _M.init()
    end
    return call(red.hget, {red, key, id}), red
  end
end

local function hgetall(red, key)
  return call(red.hgetall, {red, key})
end

local function hset(red, key, id, value)
  if CACHING_ENABLED then
    local cachedmap = c:get(key)
    if cachedmap ~= nil then
      cachedmap:set(id, value, CACHE_TTL)
      c:set(key, cachedmap, CACHE_TTL)
      return red:hset(key, id, value)
    else
      local val = lrucache.new(CACHE_SIZE)
      val:set(id, value, CACHE_TTL)
      c:set(key, val, CACHE_TTL)
    end
  end
  return call(red.hset, {red, key, id, value})
end

local function expire(red, key, ttl)
  if CACHING_ENABLED then
    local cached = c:get(key)
    local value = ''
    if cached ~= nil then -- just put it back in the cache with a ttl
      value = cached
    end
    c:set(key, value, ttl)
  end
  return call(red.expire, {red, ttl})
end

local function del(red, key)
  if CACHING_ENABLED then
    c:delete(key)
  end
  return call(red.del, {red, key})
end

local function hdel(red, key, id)
  if CACHING_ENABLED then
    local cachecontents = c:get(key)
    if cachecontents ~= nil then
      cachecontents:del(id)
      c:set(key, cachecontents, CACHE_TTL)
    end
  end
  return call(red.hdel, {red, key, id})
end

local function set(red, key, value)
  return call(red.set, {red, key, value})
end

local function smembers(red, key)
  return call(red.smembers, {red, key})
end

local function srem(red, key, id)
  return call(red.srem, {red, key, id})
end

local function sadd(red, key, id)
  return call(red.sadd, {red, key, id})
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
    local snapshotId = _M.getSnapshotId(red, apiObj.tenantId)
    -- Delete all resources for the existingAPI
    local basePath = existingAPI.basePath:sub(2)
    for path in pairs(existingAPI.resources) do
      local gatewayPath = ngx.unescape_uri(utils.concatStrings({basePath, ngx.escape_uri(path)}))
      gatewayPath = gatewayPath:sub(1,1) == "/" and gatewayPath:sub(2) or gatewayPath
      local redisKey = utils.concatStrings({"resources:", existingAPI.tenantId, ":", gatewayPath})
      _M.deleteResource(red, redisKey, REDIS_FIELD, snapshotId)
      local indexKey = utils.concatStrings({"resources:", existingAPI.tenantId, ":__index__"})
      _M.deleteResourceFromIndex(red, indexKey, redisKey, snapshotId)
    end
  end
  -- Add new API
  apiObj = cjson.encode(apiObj):gsub("\\", "")
  local ok, err = hset(red, "apis", id, apiObj)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to save the API: ", err}))
  end
  return cjson.decode(apiObj)
end

--- Get all APIs from redis
-- @param red Redis client instance
function _M.getAllAPIs(red)
  local res, err = hgetall(red, "apis")
  if not res then
    request.err(500, utils.concatStrings({"Failed to retrieve APIs: ", err}))
  end
  return res
end

--- Get a single API from redis given its id
-- @param red Redis client instance
-- @param id id of API to get
function _M.getAPI(red, id)
  local api, err = hget(red, "apis", id)
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
  local ok, err = hdel(red, "apis", id)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete the API: ", err}))
  end
end

function _M.resourceToApi(red, resource, snapshotId)
  if snapshotId ~= nil then
    resource = utils.concatStrings({'snapshots:', snapshotId, ':', resource})
  end

  resource = hget(red, resource, "resources")
  if resource == ngx.null then
    return nil
  end

  resource = cjson.decode(resource)
  return resource.apiId
end
-----------------------------
--------- Resources ---------
-----------------------------

--- Generate Redis object for resource
-- @param ops list of operations for a given resource
-- @param apiId resource api id (nil if no api)
-- @param tenantObj tenant information
function _M.generateResourceObj(ops, apiId, tenantObj, cors)
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
  if cors then
    resourceObj.cors = cors
  end
  if apiId then
    resourceObj.apiId = apiId
  end
  if tenantObj then
    resourceObj.tenantId = tenantObj.id
    resourceObj.tenantNamespace = tenantObj.namespace
    resourceObj.tenantInstance = tenantObj.instance
  end
  return cjson.encode(resourceObj)
end

--- Create/update resource in redis
-- @param red redis client instance
-- @param key redis resource key
-- @param field redis resource field
-- @param resourceObj redis object containing operations for resource
function _M.createResource(red, key, field, resourceObj, snapshotId)
  if snapshotId ~= nil then
    key = utils.concatStrings({'snapshots:', snapshotId, ':', key})
  end
  -- Add/update resource to redis
  local ok, err = hset(red, key, field, resourceObj)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to save the resource: ", err}))
  end
end

--- Add resource key to index set
-- @param red redis client instance
-- @param index index key
-- @param resourceKey resource key to add
function _M.addResourceToIndex(red, index, resourceKey, snapshotId)
  if snapshotId ~= nil then
    index = utils.concatStrings({'snapshots:', snapshotId, ':', index})
  end
  local ok, err = sadd(red, index, resourceKey)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to update the resource index set: ", err}))
  end
end

--- Delete resource key from index set
-- @param red redis client instance
-- @param index index key
-- @param key resourceKey key to delete
function _M.deleteResourceFromIndex(red, index, resourceKey, snapshotId)
  if snapshotId ~= nil then
    index = utils.concatStrings({'snapshots:', snapshotId, ':', index})
  end
  local ok, err = srem(red, index, resourceKey)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to update the resource index set: ", err}))
  end
end

--- Get resource in redis
-- @param red redis client instance
-- @param key redis resource key
-- @param field redis resource field
-- @param snapshotId an optional snapshotId
-- @return resourceObj redis object containing operations for resource
function _M.getResource(red, key, field, snapshotId)
  if snapshotId ~= nil then
    key = utils.concatStrings({"snapshots:", snapshotId, ":", key})
  end
  local resourceObj, err = hget(red, key, field)
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
function _M.getAllResources(red, tenantId, snapshotId)
  local key = utils.concatStrings({'resources:', tenantId, ':__index__'})
  if snapshotId ~= nil then
    key = utils.concatStrings({'snapshots:', snapshotId, ':', key})
  end
  local keys, err = smembers(red, key)
  if not keys then
    request.err(500, utils.concatStrings({"Failed to retrieve resource keys: ", err}))
  end
  local result = {}
  for _, v in ipairs(keys) do
    local str = v:gsub(utils.concatStrings({'snapshots:', snapshotId, ':', ''}), '')
    table.insert(result, str)
  end
  return result
end

--- Delete resource in redis
-- @param red redis client instance
-- @param key redis resource key
-- @param field redis resource field
function _M.deleteResource(red, key, field, snapshotId)
  if snapshotId ~= nil then
    key = utils.concatStrings({'snapshots:', snapshotId, ':', key})
  end
  local resourceObj, err_hget = hget(red, key, field)
  if not resourceObj then
    request.err(500, utils.concatStrings({"Failed to delete the resource: ", err_hget}))
  end
  if resourceObj == ngx.null then
    request.err(404, "Resource doesn't exist.")
  end
  -- Delete redis resource
  local ok, err_del = del(red, key)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete the resource: ", err_del}))
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
  local ok, err = hset(red, "tenants", id, tenantObj)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to add the tenant: ", err}))
  end
  return tenantObj
end

function _M.getSnapshotId(red, tenantId)
 local result = red:get(utils.concatStrings({'snapshots:tenant:', tenantId}))
  if result == ngx.null then
    return nil
  end
  return result
end

--- Get all tenants from redis
-- @param red Redis client instance
function _M.getAllTenants(red)
  local res, err = hgetall(red, "tenants")
  if not res then
    request.err(500, utils.concatStrings({"Failed to retrieve tenants: ", err}))
  end
  return res
end

--- Get a single tenant from redis given its id
-- @param red Redis client instance
-- @param id id of tenant to get
function _M.getTenant(red, id)
  local tenant, err = hget(red, "tenants", id)
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
  local ok, err = hdel(red, "tenants", id)
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
function _M.createSubscription(red, key, snapshotId)
  if snapshotId ~= nil then
    key = utils.concatStrings({'snapshots:', snapshotId, ':', key})
  end
  -- Add/update a subscription key to redis
  local ok, err = set(red, key, '')
  if not ok then
    request.err(500, utils.concatStrings({"Failed to add the subscription key", err}))
  end
end

--- Delete subscription/apikey int redis
-- @param red redis client instance
-- @param key redis subscription key to delete
function _M.deleteSubscription(red, key, snapshotId)
  if snapshotId ~= nil then
    key = utils.concatStrings({'snapshots:', snapshotId, ':', key})
  end
  local subscription, err_get = get(red, key)
  if not subscription then
    request.err(500, utils.concatStrings({"Failed to delete the subscription key: ", err_get}))
  end
  if subscription == ngx.null then
    request.err(404, "Subscription doesn't exist.")
  end
  local ok, err_del = del(red, key)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete the subscription key: ", err_del}))
  end
end

function _M.cleanSubscriptions(red, pattern)
  return red:eval("return redis.call('del', unpack(redis.call('keys', ARGV[1])))", 0, pattern)
end


function _M.getSubscriptions(red, artifactId, tenantId, snapshotId)
  local res = red:scan(0, "match", utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId, ":*"}))
  local cursor = res[1]
  local subscriptions = {}
  for _, v in pairs(res[2]) do
    local matched = {string.match(v, "subscriptions:tenant:([^:]+):api:([^:]+):([^:]+):([^:]+):*")}
    subscriptions[#subscriptions + 1] = matched[4]
  end
  while cursor ~= "0" do
    res = red:scan(cursor, "match", utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId, ":*"}))
    cursor = res[1]
    for _, v in pairs(res[2]) do
      local matched = {string.match(v, "subscriptions:tenant:([^:]+):api:([^:]+):([^:]+):([^:]+):*")}
      subscriptions[#subscriptions + 1] = matched[4]
    end
  end
  return subscriptions
end

-----------------------------
--- OAuth Tokens          ---
-----------------------------
function _M.getOAuthToken(red, provider, token)
  return get(red, utils.concatStrings({'oauth:providers:', provider, ':tokens:', token}))
end



function _M.saveOAuthToken(red, provider, token, body, ttl)
  set(red, utils.concatStrings({'oauth:providers:', provider, ':tokens:', token}), body)
  if ttl ~= nil then
    expire(red, utils.concatStrings({'oauth:providers:', provider, ':tokens:', token}), ttl)
  end
end



--- Check health of gateway
function _M.healthCheck()
  request.success(200,  "Status: Gateway ready.")
end

-----------------------------
-------- v2 Swagger ---------
-----------------------------

function _M.addSwagger(red, id, swagger)
  swagger = cjson.encode(swagger)
  local ok, err = hset(red, "swagger", id, swagger)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to add swagger: ", err}))
  end
  return cjson.decode(swagger)
end

function _M.getSwagger(red, id)
  local swagger, err = hget(red, "swagger", id)
  if not swagger then
    request.err(500, utils.concatStrings({"Failed to add swagger: ", err}))
  end
  if swagger == ngx.null then
    return nil
  end
  return cjson.decode(swagger)
end

function _M.deleteSwagger(red, id)
  local existing = _M.getSwagger(red, id)
  if existing == nil then
    request.err(404, 'Swagger doesn\'t exist')
  end
  local ok, err = hdel(red, "swagger", id)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete swagger: ", err}))
  end
end

function _M.setRateLimit(red, key, value, interval, expires)
  return red:set(key, value, interval, expires)
end

-- rate limiting is kind of special in that I don't want to get it from the cache because the intervals are too small.
-- eventually may consider moving it into an nginx variable instead of redis
function _M.getRateLimit(red, key)
  if red == nil then
    red = _M.init()
  end
  return red:get(key), red
end

function _M.optimizedLookup(red, tenant, path)
  if CACHING_ENABLED then
    local cached = c:get(utils.concatStrings({'fastmap:', tenant, ':', path}))
    if cached ~= nil then
      return cached
    end
  end
  local script = [[
    local tenant = ']] .. tenant .. [['
    local path = ']] .. path .. [['
    if redis.call('EXISTS', 'resources:' .. tenant .. ':' .. path) ~= 0 then
      return 'resources:' .. tenant .. ':' .. path
    end
    local currStr = 'fastmap:' .. tenant
    path = string.match(path, '[^?]*')
    local exp_path = string.gmatch(path, '[^/]*')
    local path = {}

    for i in exp_path do
      if i ~= nil and i ~= '' then
        table.insert(path, i)
      end
    end

    for i,v in ipairs(path) do
      if redis.call('EXISTS', currStr .. '/' .. v) == 1 then
        currStr = currStr .. '/' .. v
      elseif redis.call('EXISTS', currStr .. '/.*') == 1 then
        currStr = currStr .. '/.*'
      else
        return 0
      end
    end
    return redis.call('GET', currStr)
  ]]
  if red == nil then
    red = _M.init()
  end
  local result = red:eval(script, 0)
  if type(result) ~= 'string' or result == '' then
    return nil, red
  end
  ngx.var.gatewayPath = result:gsub(utils.concatStrings({'resources:', tenant, ':'}), '')

  if CACHING_ENABLED then
    c:set(utils.concatStrings({'fastmap:', tenant, ':', path}), result, CACHE_TTL)
  end

  return result, red
end

function _M.optimizeLookup(red, tenant, resourceKey, pathStr)
  local startingString = utils.concatStrings({'fastmap:', tenant})
  if get(red, startingString) == nil then
    set(red, startingString, '')
  end
  local path = {}
  local key = {}
  for p in string.gmatch(pathStr, '[^/]*') do
    if p ~= '' then
      table.insert(path, p)
    end
  end

  for r in string.gmatch(resourceKey:gsub('[^:]*:[^:]*:', ''), '[^/]*') do
    if r ~= '' then
      table.insert(key, r)
    end
  end

  for i = 1, table.getn(path) do
    if path[i] == key[i] then
      startingString = utils.concatStrings({startingString, '/', key[i]})
      if (exists(red, startingString)) == 0 then
        set(red, startingString, '')
      end
    else
      startingString = utils.concatStrings({startingString, '/.*'})
      if (exists(red,startingString) == 0) then
        set(red, startingString, '')
      end
    end
  end
  set(red, startingString, resourceKey)
end

function _M.lockSnapshot(red, snapshotId)
  red:set(utils.concatStrings({'lock:snapshots:', snapshotId}), 'true')
  red:expire(utils.concatStrings({'lock:snapshots:', snapshotId}), 60)
end

_M.get = get
_M.set = set
_M.exists = exists
_M.expire = expire
return _M
