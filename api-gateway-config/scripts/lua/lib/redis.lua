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

local REDIS_FIELD = "resources"
local BASE_CONF_DIR = "/etc/api-gateway/managed_confs/"

local _M = {}

--- Initialize and connect to Redis
-- @param host
-- @param port
-- @param password
-- @param timeout
function _M.init(host, port, password, timeout)
  local redis = require "resty.redis"
  local red   = redis:new()
  red:set_timeout(timeout)

  -- Connect to Redis server
  local retryCount = 4
  local connect, err = red:connect(host, port)
  while not connect and retryCount > 0 do
    local msg = utils.concatStrings({"Failed to conect to redis. Retrying ", retryCount, " more times."})
    if retryCount == 1 then
      msg = utils.concatStrings({msg:sub(1, -3), "."})
    end
    logger.info(msg)
    retryCount = retryCount - 1
    connect, err = red:connect(host, port)
  end
  if not connect then
    ngx.status = 500
    ngx.say(utils.concatStrings({"Failed to connect to redis: ", err}))
    ngx.exit(ngx.status)
  end

  -- Authenticate with Redis
  if password ~= nil and password ~= "" then
    local res, err = red:auth(password)
    if not res then
      ngx.status = 500
      ngx.say(utils.concatStrings({"Failed to authenticate: ", err}))
      ngx.exit(ngx.status)
    end
  end

  return red
end

--- Add current redis connection in the ngx_lua cosocket connection pool
-- @param red
function _M.close(red)
  -- put it into the connection pool of size 100, with 10 seconds max idle time
  local ok, err = red:set_keepalive(10000, 100)
  if not ok then
    ngx.status = 500
    ngx.say("failed to set keepalive: ", err)
    ngx.exit(ngx.status)
  end
end

--- Generate Redis object for resource
-- @param red
-- @param key
-- @param gatewayMethod
-- @param backendUrl
-- @param backendMethod
-- @param apiId
-- @param policies
-- @param security
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
-- @param red
-- @param key
-- @param field
-- @param resourceObj
function _M.createResource(red, key, field, resourceObj)
  -- Add/update resource to redis
  local ok, err = red:hset(key, field, resourceObj)
  if not ok then
    ngx.status = 500
    ngx.say(utils.concatStrings({"Failed adding Resource to redis: ", err}))
    ngx.exit(ngx.status)
  end
end

--- Get resource in redis
-- @param red
-- @param key
-- @param field
-- @return resourceObj
function _M.getResource(red, key, field)
  local resourceObj, err = red:hget(key, field)
  if not resourceObj then
    ngx.status = 500
    ngx.say("Error getting resource: ", err)
    ngx.exit(ngx.status)
  end

  -- return nil if resource doesn't exist
  if resourceObj == ngx.null then
    return nil
  end

  return resourceObj
end

--- Delete resource int redis
-- @param red
-- @param key
-- @param field
function _M.deleteResource(red, key, field)
  local resourceObj, err = red:hget(key, field)
  if not resourceObj then
    ngx.status = 500
    ngx.say("Error deleting resource: ", err)
    ngx.exit(ngx.status)
  end

  if resourceObj == ngx.null then
    ngx.status = 404
    ngx.say("Resource doesn't exist.")
    ngx.exit(ngx.status)
  end

  local ok, err = red:del(key)
  if not ok then
    ngx.status = 500
    ngx.say("Error deleing resource: ", err)
    ngx.exit(ngx.status)
  end
end

--- Create/update subscription/apikey in redis
-- @param red
-- @param key
function _M.createSubscription(red, key)
  -- Add/update a subscription key to redis
  local ok, err = red:set(key, "")
  if not ok then
    ngx.status = 500
    ngx.say(utils.concatStrings({"Failed adding subscription to redis: ", err}))
    ngx.exit(ngx.status)
  end
end

--- Delete subscription/apikey int redis
-- @param red
-- @param key
function _M.deleteSubscription(red, key)
  local ok, err = red:del(key, "subscriptions")
  if not ok then
    ngx.status = 500
    ngx.say("Error deleting subscription: ", err)
    ngx.exit(ngx.status)
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
    ngx.status = 500
    ngx.say("Failed setting notify-keyspace-events: ", err)
    ngx.exit(ngx.status)
  end

  local ok, err = redisSubClient:psubscribe("__keyspace@0__:resources:*:*")
  if not ok then
    ngx.status = 500
    ngx.say("Subscribe error: ", err)
    ngx.exit(ngx.status)
  end

  ngx.say("\nSubscribed to redis and listening for key changes...")
  ngx.flush(true)

  subscribe(redisSubClient, redisGetClient, ngx)
  ngx.exit(ngx.status)
end

--- Sync with redis on startup and create conf files for resources that are already in redis
-- @param red
function syncWithRedis(red)
  logger.info("\nCreating nginx conf files for existing resources...")
  local redisKeys, err = red:keys("*")
  if not redisKeys then
    ngx.status = 500
    ngx.say("Sync error: ", err)
    ngx.exit(ngx.status)
  end

  -- Find all redis keys with "resources:*:*"
  local resourcesExist = false
  for k, redisKey in pairs(redisKeys) do
    local index = 1
    local namespace = ""
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
          namespace = word
        elseif index == 3 then
          gatewayPath = word
          -- Create new conf file
          local resourceObj = _M.getResource(red, redisKey, REDIS_FIELD)
          local fileLocation = filemgmt.createResourceConf(BASE_CONF_DIR, namespace, ngx.escape_uri(gatewayPath), resourceObj)
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
      local namespace = ""
      for word in string.gmatch(res[3], '([^:]+)') do
        if index == 2 then
          redisKey = utils.concatStrings({redisKey, word, ":"})
        elseif index == 3 then
          namespace = word
          redisKey = utils.concatStrings({redisKey, namespace, ":"})
        elseif index == 4 then
          gatewayPath = word
          redisKey = utils.concatStrings({redisKey, gatewayPath})
        end
        index = index + 1
      end

      local resourceObj = _M.getResource(redisGetClient, redisKey, REDIS_FIELD)

      if resourceObj == nil then
        local fileLocation = filemgmt.deleteResourceConf(BASE_CONF_DIR, namespace, ngx.escape_uri(gatewayPath))
        logger.info(utils.concatStrings({"Redis key deleted: ", redisKey}))
        logger.info(utils.concatStrings({"Deleted file: ", fileLocation}))
      else
        local fileLocation = filemgmt.createResourceConf(BASE_CONF_DIR, namespace, ngx.escape_uri(gatewayPath), resourceObj)
        logger.info(utils.concatStrings({"Redis key updated: ", redisKey}))
        logger.info(utils.concatStrings({"Updated file: ", fileLocation}))
      end
    end
  end
  ngx.exit(ngx.status)
end


--- Unsubscribe from redis
function _M.unsubscribe(red)
  local ok, err = red:unsubscribe("__keyspace@0__:resources:*:*")
  if not ok then
    ngx.status = 500
    ngx.say("Unsubscribe error: ", err)
    ngx.exit(ngx.status)
  end

  _M.close(red, ngx)

  ngx.say("Unsubscribed from redis")
  ngx.exit(ngx.status)
end

return _M
