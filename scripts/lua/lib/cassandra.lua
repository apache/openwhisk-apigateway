local CASSANDRA_KEYSPACE = os.getenv('CASSANDRA_KEYSPACE')
local CASSANDRA_HOST = os.getenv('CASSANDRA_HOST')
local CASSANDRA_PORT = os.getenv('CASSANDRA_PORT')
local request = require 'lib/request'
local cjson = require 'cjson'
local utils = require 'lib/utils'
local _M = {}
local started = true
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

function _M.createTables(session)
  local keyspace_created, err = session:execute([[
  CREATE KEYSPACE ]] .. CASSANDRA_KEYSPACE .. [[ WITH REPLICATION =
    {'class':'NetworkTopologyStrategy', 'datacenter1':1} AND DURABLE_WRITES=false]])
  if err then
    print ('error creating keyspace: ' .. cjson.encode(err))
  end
  local table_created, err = session:execute([[
    CREATE TABLE IF NOT EXISTS ]] .. CASSANDRA_KEYSPACE .. [[.tenant (
      tenant_id varchar PRIMARY KEY,
      namespace varchar,
      instance varchar)
  ]])
  if err then
    request.err(503, utils.concatStrings({'Error creating cassandra tables: ', cjson.encode(err)}))
  end
  local table_created, err = session:execute([[
    CREATE TABLE IF NOT EXISTS ]] .. CASSANDRA_KEYSPACE .. [[.api (
      api_id varchar PRIMARY KEY,
      tenant_id varchar
    )
  ]])

 if err then
    request.err(503, utils.concatStrings({'Error creating cassandra tables: ', cjson.encode(err)}))
  end
  local table_created, err = session:execute([[
    CREATE TABLE IF NOT EXISTS ]] .. CASSANDRA_KEYSPACE .. [[.resource (
      tenant_id varchar PRIMARY KEY, 
      resource_path varchar PRIMARY KEY,
      api_id varchar,
      cors varchar,
      value varchar,
      PRIMARY KEY(tenant_id, resource_path)
    )
  ]])
 
  if err then
    request.err(503, utils.concatStrings({'Error creating cassandra tables: ', cjson.encode(err)}))
  end

  local table_created, err = session:execute([[
    CREATE TABLE IF NOT EXISTS ]] .. CASSANDRA_KEYSPACE .. [[.subscription (
      key varchar PRIMARY KEY,
      scope varchar,
      value varchar
    )
  ]])
  if err then
    request.err(503, utils.concatStrings({'Error creating cassandra tables: ', cjson.encode(err)}))
  end

  local table_created, err = session:execute([[
    CREATE TABLE IF NOT EXISTS ]] .. CASSANDRA_KEYSPACE .. [[.oauth (
      token varchar PRIMARY KEY,
      provider varchar PRIMARY KEY,
      value varchar,
      PRIMARY KEY(provider, token)
    )
  ]])
  started = true
  local table_created, err = session:execute([[
    CREATE TABLE IF NOT EXISTS ]] .. CASSANDRA_KEYSPACE .. [[.ratelimit (
      key varchar PRIMARY_KEY,
      value varchar,
      interval int
    )
  ]])

  if err then
    request.err(503, utils.concatStrings({'Error creating cassandra tables: ', cjson.encode(err)}))
  end
end

function _M.addAPI(session, id, apiObj, existingAPI)


end

function _M.getAllAPIs(session)
  local rows, err = session:execute ([[
    SELECT * FROM ]] .. CASSANDRA_KEYSPACE .. [[.api
  ]])
  local result = {} 
  for _, v in ipairs(rows) do
    local api_id = v['api_id'] 
    result[api_id] = v.value
  end
  return result
end

function _M.getAPI(session, id)
  return session:execute([[
    SELECT value FROM ]] .. CASSANDRA_KEYSPACE .. [[.api where api_id = ']] .. id .. [['
    ]])
end

function _M.deleteAPI(session, id)
  return session:execute([[
    DELETE FROM ]] .. CASSANDRA_KEYSPACE .. [[.api where api_id =']] .. id .. [['
  ]])
end

function _M.resourceToApi(session, id)
  id = id:gsub('resources:')
  local tenantId = id:gsplit(':')[0]
  local resourcePath = id:gsplit(':')[1]
  return session:execute ([[
    SELECT api_id FROM ]] .. CASSANDRA_KEYSPACE [[.resource where tenant_id=']] .. tenantId .. [[' and resource_path=']] .. resourcePath .. [['
  ]])
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
  local tenantId = stringSplit(key)[1]
  local resourcePath = stringSplit(key)[2]
  local apiId = resourceObj.apiId
  return session:execute(string.format("INSERT into %s.resource (tenant_id, resource_path, api_id) VALUES ('%s', '%s', '%s', '%s')", CASSANDRA_KEYSPACE, tenantId, resourcePath, apiId, cjson.encode(resourceObj)))
end

function _M.addResourceToIndex(session, index, resourceKey)
  return nil -- we don't need indexes
end

function _M.deleteResourceFromIndex(session, index, resourceKey)
  return nil
end


function _M.getResource(session, key, field)
  local tenantId = stringSplit(key)[1]
  local resourcePath = stringSplit(key)[2]
  return session:execute(string.format("SELECT value from %s.resource WHERE tenant_id='%s' and resource_path='%s'", CASSANDRA_KEYSPACE, tenantId, resourcePath))
end

function _M.getAllResources(session, tenantId)
  local data = session:execute(string.format("SELECT resource_path from %s.resource WHERE tenant_id='%s'", CASSANDRA_KEYSPACE, tenantId))
  local result = {}
  for _, v in ipairs(results) do
    table.insert(result, utils.concatStrings({'resources:', tenantId, ':', v})) -- emulate the redis behavior
  end
end

function _M.deleteResource(session, key, field)
  local tenantId = stringSplit(key)[1]
  local resourcePath = stringSplit(key)[2]
  return session:execute(string.format("DELETE from %s.resource WHERE tenant_id='%s' and resource_path='%s'", CASSANDRA_KEYSPACE, tenantId, resourcePath))
end

function _M.addTenant(session, id, tenantObj)
  return session:execute(string.format("INSERT into %s.tenant (tenant_id, value) VALUES ('%s', '%s')", CASSANDRA_KEYSPACE, tenantId, cjson.encode(tenantObj)))
end

function _M.getAllTenants(session)
  return session:execute(string.format("SELECT value FROM %s.tenant", CASSANDRA_KEYSPACE))

end

function _M.getTenant(session, id)
  return session:execute(string.format("SELECT value FROM %s.tenant where tenant_id='%s'", CASSANDRA_KEYSPACE, id))
end


function _M.deleteTenant(session, id)
  return session:execute(string.format("DELETE FROM %s.tenant where tenant_id='%s'", CASSANDRA_KEYSPACE, id))
end

function _M.createSubscription(session, key)
  return session:execute(string.format("INSERT into %s.subscription (key) values ('%s')", CASSANDRA_KEYSPACE, key))
end

function _M.deleteSubscription(session, key)
  return session:execute(string.format("DELETE from %s.subscription where key='%s'", CASSANDRA_KEYSPACE, key))
end


function _M.addSwagger(session, id, swagger)

end

function _M.getSwagger(session, id)

end

function _M.getOAuthToken(session, provider, token)


end

function _M.saveOAuthToken(session, provider, token, body)


end

function _M.getRateLimit(session, key)


end


function _M.setRateLimit(session, key, value, interval, expires)


end

function splitString(key)
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
