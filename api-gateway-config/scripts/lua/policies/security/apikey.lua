
local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"
local cjson = require "cjson" 

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local _M = {}


function process(securityObj)
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = ngx.var.apiId
  local scope = securityObj.scope
  local header = (securityObj.header == nil) and 'x-api-key' or securityObj.header
  local apiKey = ngx.var[utils.concatStrings({'http_', header}):gsub("-", "_")]

  if not apiKey then
    request.err(401, utils.concatStrings({'API key header "', header, '" is required.'}))
  end
  local ok = validate(tenant, gatewayPath, apiId, scope, apiKey)
  if not ok then
    request.err(401, 'Invalid API key.')
  end
  return apiKey
end

function validate(tenant, gatewayPath, apiId, scope, apiKey)
  -- Open connection to redis or use one from connection pool
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local k
  if scope == 'tenant' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant})
  elseif scope == 'resource' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':resource:', gatewayPath})
  elseif scope == 'api' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':api:', apiId})
  end
  k = utils.concatStrings({k, ':key:', apiKey})
  local exists = red:exists(k)
  redis.close(red)
  return exists == 1
end

_M.process = process
return _M
