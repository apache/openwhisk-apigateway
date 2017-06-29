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
  o.ds = o.impl.init()
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
  return self.impl.close(self.ds)
end

function DataStore:addAPI(id, apiObj, existingAPI)
  self:setSnapshotId(apiObj.tenantId)
  return self.impl.addAPI(self.ds, id, apiObj, existingAPI)
end

function DataStore:getAllAPIs()
  return self.impl.getAllAPIs(self.ds)
end

function DataStore:getAPI(id)
  return self.impl.getAPI(self.ds, id)
end

function DataStore:deleteAPI(id)
  return self.impl.deleteAPI(self.ds, id)
end

function DataStore:resourceToApi(resource)
  return self.impl.resourceToApi(self.ds, resource, self.snapshotId)
end

function DataStore:generateResourceObj(ops, apiId, tenantObj, cors)
  return self.impl.generateResourceObj(ops, apiId, tenantObj, cors)
end

function DataStore:createResource(key, field, resourceObj)
  return self.impl.createResource(self.ds, key, field, resourceObj, self.snapshotId)
end

function DataStore:addResourceToIndex(index, resourceKey)
  return self.impl.addResourceToIndex(self.ds, index, resourceKey, self.snapshotId)
end

function DataStore:deleteResourceFromIndex(index, resourceKey)
  return self.impl.deleteResourceFromIndex(self.ds, index, resourceKey, self.snapshotId)
end
function DataStore:getResource(key, field)
  return self.impl.getResource(self.ds, key, field, self.snapshotId)
end
function DataStore:getAllResources(tenantId)
  return self.impl.getAllResources(self.ds, tenantId, self.snapshotId)
end
function DataStore:deleteResource(key, field)
  return self.impl.deleteResource(self.ds, key, field, self.snapshotId)
end

function DataStore:addTenant(id, tenantObj)
  return self.impl.addTenant(self.ds, id, tenantObj)
end

function DataStore:getAllTenants()
  return self.impl.getAllTenants(self.ds)
end

function DataStore:getTenant(id)
  return self.impl.getTenant(self.ds, id)
end

function DataStore:deleteTenant(id)
  return self.impl.deleteTenant(self.ds, id)
end

function DataStore:createSubscription(key)
  return self.impl.createSubscription(self.ds, key, self.snapshotId)
end

function DataStore:deleteSubscription(key)
  return self.impl.deleteSubscription(self.ds, key, self.snapshotId)
end

function DataStore:getSubscriptions(artifactId, tenantId)
  return self.impl.getSubscriptions(artifactId, tenantId)
end

function DataStore:healthCheck()
  return self.impl.healthCheck(self.ds)
end

function DataStore:addSwagger(id, swagger)
  return self.impl.addSwagger(self.ds, id, swagger)
end

function DataStore:getSwagger(id)
  return self.impl.getSwagger(self.ds, id)
end

function DataStore:deleteSwagger(id)
  return self.impl.deleteSwagger(self.ds, id)
end

function DataStore:getOAuthToken(provider, token)
  return self.impl.getOAuthToken(self.ds, provider, token)
end

function DataStore:saveOAuthToken(provider, token, body, ttl)
  return self.impl.saveOAuthToken(self.ds, provider, token, body, ttl)
end

function DataStore:exists(key)
  return self.impl.exists(self.ds, key, self.snapshotId)
end

function DataStore:setRateLimit(key, value, interval, expires)
  return self.impl.setRateLimit(self.ds, key, value, interval, expires)
end
function DataStore:getRateLimit(key)
  return self.impl.getRateLimit(self.ds, key)
end
-- o be removed in the future

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

function _M.init()
  return DataStore:init()
end
function _M.initWithDriver(ds)
  return DataStore:initWithDriver(ds)
end
return _M
