local DATASTORE = os.getenv( 'DATASTORE')
local utils = require('lib/utils')

if DATASTORE == nil then
  DATASTORE = 'redis'
end
local _M = {}

local DataStore = {}
function DataStore:init()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.impl = require(utils.concatStrings({'lib/', DATASTORE}))
  return o
end

function DataStore:setSnapshotId(tenant)
  self.snapshotId = self.impl.getSnapshotId(self.ds, tenant)
  self:lockSnapshot(snapshotId)
  if self.snapshotId == ngx.null then
    self.snapshotId = nil
  end
end
-- right now just using this for the tests
function DataStore:initWithDriver(ds)
local o = {}
  setmetatable(o, self)
  self.__index = self
  o.impl = require('lib/redis')
  o.ds = ds
  return o
end

function DataStore:lockSnapshot(snapshotId)
  return self.impl.lockSnapshot(self.ds, snapshotId)
end

function DataStore:close()
  if self.ds == nil then
    return nil
  else
    return self.impl.close(self.ds)
  end
end

function DataStore:addAPI(id, apiObj, existingAPI)
  self:singleInit()
  self:setSnapshotId(apiObj.tenantId)
  return self.impl.addAPI(self.ds, id, apiObj, existingAPI)
end

function DataStore:getAllAPIs()
  self:singleInit()
  return self.impl.getAllAPIs(self.ds)
end

function DataStore:getAPI(id)
  local result, ds =  self.impl.getAPI(self.ds, id)
  if ds ~= nil then
    self.ds = ds
  end
  return result
end

function DataStore:deleteAPI(id)
  self:singleInit()
  return self.impl.deleteAPI(self.ds, id)
end

function DataStore:resourceToApi(resource)
  local result, ds = self.impl.resourceToApi(self.ds, resource, self.snapshotId)
  if ds ~= nil then
    self.ds = ds
  end
  return result
end

function DataStore:generateResourceObj(ops, apiId, tenantObj, cors)
  return self.impl.generateResourceObj(ops, apiId, tenantObj, cors)
end

function DataStore:createResource(key, field, resourceObj)
  self:singleInit()
  return self.impl.createResource(self.ds, key, field, resourceObj, self.snapshotId)
end

function DataStore:addResourceToIndex(index, resourceKey)
  self:singleInit()
  return self.impl.addResourceToIndex(self.ds, index, resourceKey, self.snapshotId)
end

function DataStore:deleteResourceFromIndex(index, resourceKey)
  self:singleInit()
  return self.impl.deleteResourceFromIndex(self.ds, index, resourceKey, self.snapshotId)
end
function DataStore:getResource(key, field)
  self:singleInit()
  return self.impl.getResource(self.ds, key, field, self.snapshotId)
end
function DataStore:getAllResources(tenantId)
  self:singleInit()
  return self.impl.getAllResources(self.ds, tenantId, self.snapshotId)
end
function DataStore:deleteResource(key, field)
  self:singleInit()
  return self.impl.deleteResource(self.ds, key, field, self.snapshotId)
end

function DataStore:addTenant(id, tenantObj)
  self:singleInit()
  return self.impl.addTenant(self.ds, id, tenantObj)
end

function DataStore:getAllTenants()
  self:singleInit()
  return self.impl.getAllTenants(self.ds)
end

function DataStore:getTenant(id)
  local result, ds =  self.impl.getTenant(self.ds, id)
  if ds ~= nil then
    self.ds = ds
  end
  return result
end

function DataStore:deleteTenant(id)
  self:singleInit()
  return self.impl.deleteTenant(self.ds, id)
end

function DataStore:createSubscription(key)
  self:singleInit()
  return self.impl.createSubscription(self.ds, key, self.snapshotId)
end

function DataStore:deleteSubscription(key)
  self:singleInit()
  return self.impl.deleteSubscription(self.ds, key, self.snapshotId)
end

function DataStore:getSubscriptions(artifactId, tenantId)
  self:singleInit()
  return self.impl.deleteSubscription(self.ds, key, self.snapshotId)
end

function DataStore:healthCheck()
  self:singleInit()
  return self.impl.healthCheck(self.ds)
end

function DataStore:addSwagger(id, swagger)
  self:singleInit()
  return self.impl.addSwagger(self.ds, id, swagger)
end

function DataStore:getSwagger(id)
  self:singleInit()
  return self.impl.getSwagger(self.ds, id)
end

function DataStore:deleteSwagger(id)
  self:singleInit()
  return self.impl.deleteSwagger(self.ds, id)
end

function DataStore:getOAuthToken(provider, token)
  local result, ds =  self.impl.getOAuthToken(self.ds, provider, token)
  if ds ~= nil then
    self.ds = ds
  end
  return result
end

function DataStore:saveOAuthToken(provider, token, body, ttl)
  self:singleInit()
  return self.impl.saveOAuthToken(self.ds, provider, token, body, ttl)
end

function DataStore:exists(key)
  local result, ds =  self.impl.exists(self.ds, key, self.snapshotId)
  if ds ~= nil then
    self.ds = ds
  end
  return result
end

function DataStore:setRateLimit(key, value, interval, expires)
  self:singleInit()
  return self.impl.setRateLimit(self.ds, key, value, interval, expires)
end

function DataStore:getRateLimit(key)
  local result, ds = self.impl.getRateLimit(self.ds, key)
  if ds ~= nil then
    self.ds = ds
  end
  return result
end

function DataStore:optimizedLookup(tenant, path)
  local result, ds = self.impl.optimizedLookup(self.ds, tenant, path)
  if ds ~= nil then
    self.ds = ds
  end
  return result
end

function DataStore:deleteSubscriptionAdv(artifactId, tenantId, clientId)
  local subscriptionKey = utils.concatStrings({"subscriptions:tenant:", tenantId, ":api:", artifactId})
  local key = utils.concatStrings({subscriptionKey, ":key:", clientId})
  if self:exists(key) == 1 then
    self:deleteSubscription(key)
  else
    local pattern = utils.concatStrings({subscriptionKey, ":clientsecret:" , clientId, ":*"})
    local res = self.impl.cleanSubscriptions(self.ds, pattern)
    if res == false then
      return false
    end
  end
  return true
end

function DataStore:optimizeLookup(tenant, resourceKey, pathStr)
  self:singleInit()
  return self.impl.optimizeLookup(self.ds, tenant, resourceKey, pathStr)
end


function DataStore:singleInit()
  if self.ds == nil then
    self.ds = self.impl.init()
  end
end
-- to be removed in the future

function _M.init()
  return DataStore:init()
end
function _M.initWithDriver(ds)
  return DataStore:initWithDriver(ds)
end
return _M
