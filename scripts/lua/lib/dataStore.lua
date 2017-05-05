


_M = {} 
-- this script dynamically loads a persistence plugin and uses it to make calls to the persistent datastore


local DATASTORE = os.getenv( 'DATASTORE')
local utils = require('lib/utils')

if DATASTORE == nil then 
  DATASTORE = 'redis'
end

local impl = require(utils.concatStrings({'lib/', DATASTORE}))

function _M.init() 
  return impl.init()
end 

function _M.close(ds)
  return impl.close(ds)
end

function _M.addAPI(ds, id, apiObj, existingAPI)
  return impl.addAPI(ds, id, apiObj, existingAPI)
end

function _M.getAllAPIs(ds)
  return impl.getAllAPIs(ds)
end
function _M.getAPI(ds, id)
  return impl.getAPI(ds, id)
end
function _M.deleteAPI(ds, id)
  return impl.deleteAPI(ds, id)
end

function _M.resourceToApi(ds, resource)
  return impl.resourceToApi(ds, resource)
end
function _M.generateResourceObj(ds, ops, apiId, tenantObj, cors)
  return impl.generateResourceObj(ds, ops, apiId, tenantObj, cors)
end
function _M.createResource(ds, key, field, resourceObj)
  return impl.createResource(ds, key, field, resourceObj)
end
function _M.addResourceToIndex(ds, index, resourceKey)
  return impl.addResourceToIndex(ds, index, resourceKey)
end
function _M.deleteResourceFromIndex(ds, index, resourceKey)
  return impl.deleteResourceFromIndex(ds, index, resourceKey)
end
function _M.getResource(ds, key, field)
  return impl.getResource(ds, key, field)
end
function _M.getAllResourceKeys(ds, tenantId)
  return impl.getAllResourceKeys(ds, tenantId)
end
function _M.deleteResource(ds, key, field)
  return impl.deleteResource(ds, key, field)
end
function _M.addTenant(ds, id, tenantObj)
  return impl.addTenant(ds, id, tenantObj)
end
function _M.getAllTenants(ds)
  return impl.getAllTenants(ds)
end
function _M.getTenant(ds, id)
  return impl.getTenant(ds, id)
end
function _M.deleteTenant(ds, id)
  return impl.deleteTenant(ds, id)
end
function _M.createSubscription(ds, key)
  return impl.createSubscription(ds, key)
end
function _M.deleteSubscription(ds, key)
  return impl.deleteSubscription(ds, key)
end
function _M.healthCheck(ds)
  return impl.healthCheck(ds)
end
function _M.addSwagger(ds, id, swagger)
  return impl.addSwagger(ds, id, swagger)
end

-- to be removed in the future
function _M.exists(ds, key) 
  return impl.exists(ds, key) 
end 
return _M
