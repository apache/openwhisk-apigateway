local CASSANDRA_KEYSPACE = os.getenv('CASSANDRA_KEYSPACE')
local CASSANDRA_HOST = os.getenv('CASSANDRA_HOST')
local CASSANDRA_PORT = os.getenv('CASSANDRA_PORT')
local request = require 'lib/request'
local cjson = require 'cjson'
local utils = require 'lib/utils'
local _M = {}
local started = true
function _M.setKeyspace(keyspace)
  CASSANDRA_KEYSPACE = keyspace
end

function _M.init()
  local Cluster = require 'resty.cassandra.cluster'
  if not started then
    local cluster, err = Cluster.new({
      shm = 'cassandra',
      contact_points = { utils.concatStrings({CASSANDRA_HOST})},
      keyspace = 'system',
      timeout_read = 1000
     })
    if err then
      request.err(503, utils.concatStrings({'Unable to communicate with cassandra cluster: ', cjson.encode(err)}))
    end
    _M.createTables(cluster)
  end
  local cluster, err = Cluster.new({
    shm = 'cassandra',
    contact_points = { CASSANDRA_HOST},
    keyspace = CASSANDRA_KEYSPACE,
    timeout_read = 1000
  })
  return cluster
end

function _M.addAPI(session, id, apiObj, existingAPI)
  if existingAPI == nil then
    local apis = _M.getAllAPIs(session)
    for apiId, obj in pairs(apis) do
      if apiId%2 == 0 then
        obj = cjson.decode(obj)
        if obj.tenantId == apiObj.tenantId and obj.basePath == apiObj.basePath then
          request.err(500, "basePath not unique for given tenant.")
        end
      end
    end
  else -- emulate the logic in redis.lua, just delete all the resources for a given api
    local basePath = existingAPI.basePath:sub(2)
    for path, v in pairs(existingAPI.resources) do
      local gatewayPath = ngx.unescape_uri(utils.concatStrings({basePath, ngx.escape_uri(path)}))
      gatewayPath = gatewayPath:sub(1,1) == "/" and gatewayPath:sub(2) or gatewayPath
      local redisKey = utils.concatStrings({"resources:", existingAPI.tenantId, ":", gatewayPath})
      _M.deleteResource(red, redisKey, REDIS_FIELD)
    end
  end
  local tenantId = apiObj.tenantId
  apiObj = cjson.encode(apiObj)
  local ok, err = session:execute(string.format("INSERT into %s.api (api_id, tenant_id, value) VALUES ('%s', '%s', '%s')", CASSANDRA_KEYSPACE, id, tenantId, apiObj))
  if err then
    request.err(500, 'Failed to save api: ' .. err)
  end
  return cjson.decode(apiObj)
end

function _M.getAllAPIs(session)
  local rows, err = session:execute(string.format("SELECT * from %s.api", CASSANDRA_KEYSPACE))
  local result = {}
  for _, v in ipairs(rows) do
    table.insert(result, v['api_id'])
    table.insert(result, v['value'])
  end
  return result
end

function _M.getAPI(session, id)
  local rows, err = session:execute(string.format("SELECT * from %s.api where api_id='%s'", CASSANDRA_KEYSPACE, id))
  if err then
    request.err(500, utils.concatStrings({'Error getting api: ', err}))
  end
  for _,v in ipairs(rows) do
    return v.value
  end
end

function _M.deleteAPI(session, id)
  local ok, err = session:execute(string.format("DELETE from %s.api where api_id='%s'", CASSANDRA_KEYSPACE, id))
  if err then
    request.err(500, utils.concatStrings({'Error deleting api: ', err}))
  end
end

function _M.resourceToApi(session, id)
  local spl = _M.stringSplit(id)
  local tenantId = spl[1]
  local gatewayPath = spl[2]
  local rows, err = session:execute(string.format("SELECT api_id FROM %s.resource where tenant_id='%s' and resource_path='%s'", CASSANDRA_KEYSPACE,tenantId, gatewayPath))
  if err then
    request.err(500, utils.concatStrings({'Error resolving resource to api: ', err}))
  end
  for _, v in ipairs(rows) do
    return v.api_id
  end
end

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


function _M.createResource(session, key, field, resourceObj)
  local tenantId = _M.stringSplit(key)[1]
  local resourcePath = _M.stringSplit(key)[2]
  local apiId = cjson.decode(resourceObj).apiId
  local ok, err = session:execute(string.format("INSERT into %s.resource (tenant_id, resource_path, api_id, value) VALUES ('%s', '%s', '%s', '%s')", CASSANDRA_KEYSPACE, tenantId, resourcePath, apiId, resourceObj))

  if err then
    request.err(500, utils.concatStrings({'Failed to create resource: ' .. err}))
  end
end

function _M.addResourceToIndex(session, index, resourceKey)
  return nil -- we don't need indexes
end

function _M.deleteResourceFromIndex(session, index, resourceKey)
  return nil
end


function _M.getResource(session, key, field)
  local tenantId = _M.stringSplit(key)[1]
  local resourcePath = _M.stringSplit(key)[2]
  local rows, err = session:execute(string.format("SELECT value from %s.resource WHERE tenant_id='%s' and resource_path='%s'", CASSANDRA_KEYSPACE, tenantId, resourcePath))
  for _, v in ipairs(rows) do
    return v.value
  end
end

function _M.getAllResources(session, tenantId)
  local data = session:execute(string.format("SELECT resource_path from %s.resource WHERE tenant_id='%s'", CASSANDRA_KEYSPACE, tenantId))
  local result = {}
  for _, v in ipairs(data) do
    table.insert(result, utils.concatStrings({'resources:', tenantId, ':', v['resource_path']})) -- emulate the redis behavior
  end
  return result
end

function _M.deleteResource(session, key, field)
  local tenantId = _M.stringSplit(key)[1]
  local resourcePath = _M.stringSplit(key)[2]
  local ok, err = session:execute(string.format("DELETE from %s.resource WHERE tenant_id='%s' and resource_path='%s'", CASSANDRA_KEYSPACE, tenantId, resourcePath))
  if err then
    request.err(500, 'Failed to delete resource: ' .. err)
  end
end

function _M.addTenant(session, id, tenantObj)
  local tenants = _M.getAllTenants(session)
  for tenantId, obj in pairs(tenants) do
    if tenantId%2 == 0 then
      obj = cjson.decode(obj)
      if obj.namespace == tenantObj.namespace and obj.instance == tenantObj.instance then
        return cjson.encode(obj)
      end
    end
  end
  tenantObj = cjson.encode(tenantObj)
  local ok, err = session:execute(string.format("INSERT into %s.tenant (tenant_id, value) VALUES ('%s', '%s')", CASSANDRA_KEYSPACE, id, tenantObj))
  if err then
    request.err(500, 'Error creating tenant: ' .. cjson.encode(err))
  end
  return tenantObj
end

function _M.getAllTenants(session)
  local rows, err = session:execute(string.format("SELECT * FROM %s.tenant", CASSANDRA_KEYSPACE))
  local result = {}
  if rows == nil then
    return {}
  end
  for _, v in ipairs(rows) do
    table.insert(result, v['tenant_id'])
    table.insert(result, v['value'])
  end
  return result
end

function _M.getTenant(session, id)
  local rows, err = session:execute(string.format("SELECT value FROM %s.tenant where tenant_id='%s'", CASSANDRA_KEYSPACE, id))
  for _, v in ipairs(rows) do
    return cjson.decode(v.value)
  end
end


function _M.deleteTenant(session, id)
  local ok, err = session:execute(string.format("DELETE FROM %s.tenant where tenant_id='%s'", CASSANDRA_KEYSPACE, id))
  if err then
    request.err(500, 'Error deleting tenant: ' .. err)
  end
end

function _M.createSubscription(session, key)
  return session:execute(string.format("INSERT into %s.subscription (key) values ('%s')", CASSANDRA_KEYSPACE, key))
end

function _M.deleteSubscription(session, key)
  return session:execute(string.format("DELETE from %s.subscription where key='%s'", CASSANDRA_KEYSPACE, key))
end


function _M.addSwagger(session, id, swagger)
  local ok, err = session:execute(string.format("INSERT into %s.swagger (swagger_id, value) VALUES ('%s', '%s')", CASSANDRA_KEYSPACE, id, swagger))
  if err then
    request.err(500, utils.concatStrings({'Error saving swagger: ', err}))
  end
end

function _M.getSwagger(session, id)
  local rows, err = session:execute(string.format("SELECT value FROM %s.swagger where swagger_id='%s'", CASSANDRA_KEYSPACE, id))
  if err then
    request.err(500, utils.concatStrings({'Error getting swagger: ', err}))
  end
  for _, v in ipairs(rows) do
    return v.value
  end
end

function _M.getOAuthToken(session, provider, token)
  local rows, err = session:execute(string.format("SELECT value FROM %s.oauth where provider='%s' and oauth_token='%s'", CASSANDRA_KEYSPACE, provider, token))
  if err then
    request.err(utils.concatStrings({500, 'Error getting oauth token: ', err}))
  end
  for _, v in ipairs(rows) do
    return v.value
  end
end

function _M.saveOAuthToken(session, provider, token, body)
  local ok, err = session:execute(string.format("INSERT INTO %s.oauth (provider, oauth_token, value) VALUES ('%s', '%s', '%s')", CASSANDRA_KEYSPACE, provider, token, cjson.encode(body)))
  if err then
    request.err(500, utils.concatStrings({'Error setting oauth token: ', err}))
  end
  return nil
end

function _M.subscriptionExists(session, key)
  local rows, err = session.execute(string.format("SELECT * from %s.subscription where key='%s'", CASSANDRA_KEYSPACE, key))
  if err then
    request.err(500, utils.concatStrings({'Error retrieving subscription: ', err}))
  end
  if #rows > 0 then
    return 1
  end
  return 0
end

function _M.getRateLimit(session, key)
  local ok, err = session:execute(string.format("SELECT * from %s.ratelimit where key='%s'", CASSANDRA_KEYSPACE, key))
  if err then
    request.err(500, utils.concatStrings({'Error retrieviing ratelimiting key: ', err}))
  end
end


function _M.setRateLimit(session, key, value, interval, expires)
  local ok, err = session:execute(string.format("INSERT into %s.ratelimit (key) VALUES ('%s') USING TTL %d", CASSANDRA_KEYSPACE, key, expires))
  if err then
    request.err(500, utils.concatStrings({'Error setting ratelimiting key: ', err}))
  end
  return nil
end

function _M.stringSplit(key)
  local result = {}
  local splitter = key:gmatch('[^:]*')
  result[0] = splitter()
  splitter()
  result[1] = splitter()
  splitter()
  result[2] = splitter()
  return result
end

function _M.close()
  return nil
end

return _M
