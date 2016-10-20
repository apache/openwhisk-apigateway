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

--- @module
--
-- @author Alex Song (songs)

local cjson = require "cjson"
local filemgmt = require "lib/filemgmt"
local utils = require "lib/utils"
local logger = require "lib/logger"
local request = require "lib/request"

local REDIS_FIELD = "resources"
local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local _M = {}

--- Initialize and connect to Redis
-- @param host redis host
-- @param port redis port
-- @param password redis password (nil if no password)
-- @param timeout redis timeout in milliseconds
function _M.init(host, port, password, timeout)
  local redis = require "resty.redis"
  local red   = redis:new()
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

--- Generate Redis object for resource
-- @param red redis client instance
-- @param key redis resource key
-- @param gatewayMethod resource gateway method
-- @param backendUrl resource backend url
-- @param backendMethod resource backend method
-- @param apiId resource api id (nil if no api)
-- @param policies list of policy objects
-- @param security security object
function _M.generateResourceObj(red, key, gatewayMethod, backendUrl, backendMethod, apiId, policies, security)
  local newResource
  local resourceObj = _M.getResource(red, key, REDIS_FIELD)
  if resourceObj == nil then
    newResource = {
      operations = {
        [gatewayMethod] = {
          backendUrl = backendUrl,
          backendMethod = backendMethod,
        }
      }
    }
  else
    newResource = cjson.decode(resourceObj)
    newResource.operations[gatewayMethod] = {
      backendUrl = backendUrl,
      backendMethod = backendMethod,
    }
  end
  if apiId then
    newResource.apiId = apiId
  end
  if policies then
    newResource.operations[gatewayMethod].policies = policies
  end
  if security then
    newResource.operations[gatewayMethod].security = security
  end
  return cjson.encode(newResource)
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
    request.err(500, utils.concatStrings({"Failed adding resource to redis: ", err})) 
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
    request.err(500, utils.concatStrings({"Failed getting resource: ", err}))
  end
  -- return nil if resource doesn't exist
  if resourceObj == ngx.null then
    return nil
  end

  return resourceObj
end

--- Delete resource int redis
-- @param red redis client instance
-- @param key redis resource key
-- @param field redis resource field
function _M.deleteResource(red, key, field)
  local resourceObj, err = red:hget(key, field)
  if not resourceObj then
    request.err(500, utils.concatStrings({"Failed deleting resource: ", err}))
  end
  if resourceObj == ngx.null then
    request.err(404, "Resource doesn't exist.")
  end
  local ok, err = red:del(key)
  if not ok then
    request.err(500, utils.concatStrings({"Failed deleting resource: ", err}))
  end
end

--- Create/update subscription/apikey in redis
-- @param red redis client instance
-- @param key redis subscription key to create
function _M.createSubscription(red, key)
  -- Add/update a subscription key to redis
  local ok, err = red:set(key, true)
  if not ok then
    request.err(500, utils.concatStrings({"Failed adding subscription to redis", err}))
  end
end

--- Delete subscription/apikey int redis
-- @param red redis client instance
-- @param key redis subscription key to delete
function _M.deleteSubscription(red, key)
  local subscription, err = red:get(key)
  if not subscription then
    request.err(500, utils.concatStrings({"Failed to delete subscription: ", err}))
  end
  if subscription == ngx.null then
    request.err(404, "Subscription doesn't exist.")
  end
  local ok, err = red:del(key)
  if not ok then
    request.err(500, utils.concatStrings({"Failed to delete subscription: ", err}))
  end
end

--- Subscribe to redis
-- @param redisSubClient the redis client that is listening for the redis key changes
-- @param redisGetClient the redis client that gets the changed resource to update the conf file
function _M.subscribe(redisSubClient, redisGetClient)
  -- create conf files for existing resources in redis
  syncWithRedis(redisGetClient, ngx)
  -- enable keyspace notifications
  local ok, err = redisGetClient:config("set", "notify-keyspace-events", "KEA")
  if not ok then
    request.err(500, utils.concatStrings({"Failed setting notify-keyspace-events: ", err}))
  end
  ok, err = redisSubClient:psubscribe("__keyspace@0__:resources:*:*")
  if not ok then
    request.err(500, utils.concatStrings({"Failed to subscribe to redis: ", err}))
  end
  ngx.say("\nSubscribed to redis and listening for key changes...")
  ngx.flush(true)
  subscribe(redisSubClient, redisGetClient, ngx)
  ngx.exit(ngx.status)
end

--- Sync with redis on startup and create conf files for resources that are already in redis
-- @param red redis client instance
function syncWithRedis(red)
  logger.info("\nCreating nginx conf files for existing resources...")
  local redisKeys, err = red:keys("*")
  if not redisKeys then
    request.err(500, util.concatStrings({"Failed to sync with Redis: ", err}))
  end
  -- Find all redis keys with "resources:*:*"
  local resourcesExist = false
  for k, redisKey in pairs(redisKeys) do
    local index = 1
    local tenant = ""
    local gatewayPath = ""
    for word in string.gmatch(redisKey, '([^:]+)') do
      if index == 1 then
        if word ~= "resources" then
          break
        else
          resourcesExist = true
          index = index + 1
        end
      else
        if index == 2 then
          tenant = word
        elseif index == 3 then
          gatewayPath = word
          -- Create new conf file
          local resourceObj = _M.getResource(red, redisKey, REDIS_FIELD)
          local fileLocation = filemgmt.createResourceConf(BASE_CONF_DIR, tenant, ngx.escape_uri(gatewayPath), resourceObj)
          logger.info(utils.concatStrings({"Updated file: ", fileLocation}))
        end
        index = index + 1
      end
    end
  end
  if resourcesExist == false then
    logger.info("No existing resources.")
  end
end

--- Subscribe helper method
-- Starts a while loop that listens for key changes in redis
-- @param redisSubClient the redis client that is listening for the redis key changes
-- @param redisGetClient the redis client that gets the changed resource to update the conf file
function subscribe(redisSubClient, redisGetClient)
  while true do
    local res, err = redisSubClient:read_reply()
    if not res then
      if err ~= "timeout" then
        ngx.say("Read reply error: ", err)
        ngx.exit(ngx.status)
      end
    else
      local index = 1
      local redisKey = ""
      local tenant = ""
      local gatewayPath = ""
      for word in string.gmatch(res[3], '([^:]+)') do
        if index == 2 then
          redisKey = utils.concatStrings({redisKey, word, ":"})
        elseif index == 3 then
          tenant = word
          redisKey = utils.concatStrings({redisKey, tenant, ":"})
        elseif index == 4 then
          gatewayPath = word
          redisKey = utils.concatStrings({redisKey, gatewayPath})
        end
        index = index + 1
      end
      local resourceObj = _M.getResource(redisGetClient, redisKey, REDIS_FIELD)
      if resourceObj == nil then
        local fileLocation = filemgmt.deleteResourceConf(BASE_CONF_DIR, tenant, ngx.escape_uri(gatewayPath))
        logger.info(utils.concatStrings({"Redis key deleted: ", redisKey}))
        logger.info(utils.concatStrings({"Deleted file: ", fileLocation}))
      else
        local fileLocation = filemgmt.createResourceConf(BASE_CONF_DIR, tenant, ngx.escape_uri(gatewayPath), resourceObj)
        logger.info(utils.concatStrings({"Redis key updated: ", redisKey}))
        logger.info(utils.concatStrings({"Updated file: ", fileLocation}))
      end
    end
  end
  ngx.exit(ngx.status)
end


--- Unsubscribe from redis
-- @param red redis client instance
function _M.unsubscribe(red)
  local ok, err = red:unsubscribe("__keyspace@0__:resources:*:*")
  if not ok then
    request.err(500, utils.concatStrings({"Failed to unsubscribe to redis: ", err}))
  end
  _M.close(red, ngx)
  ngx.say("Unsubscribed from redis")
  ngx.exit(ngx.status)
end

return _M
