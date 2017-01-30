local _M = {}

local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

local resty_sha256 = require "resty.sha256"
local resty_str = require "resty.string" 

function process(securityObj) 
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = ngx.var.apiId
  local scope = securityObj.scope
  local clientId = ngx.var[utils.concatStrings({'http_', 'X-Client-ID'}):gsub("-", "_")]
  if not clientId then
    request.err(401, "X-Client-ID is required.")
  end

  local clientSecret = ngx.var[utils.concatStrings({'http_', 'X-Client-Secret'}):gsub("-","_")]
  if not clientSecret then
    request.err(401, "X-Client-Secret is required")
  end
  
  local sha256 = resty_sha256:new() 
  sha256:update(clientSecret)  
  local digest = sha256:final()
  local result = validate(tenant, gatewayPath, apiId, scope, clientId, resty_str.to_hex(digest))
  if not result then
    request.err(401, "Secret mismatch or not subscribed to this api.")
  end

end

function validate(tenant, gatewayPath, apiId, scope, clientId, clientSecret)
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



  k = utils.concatStrings({k, ':clientsecret:', clientId, ':', clientSecret})
  local exists = red:exists(k)
  redis.close(red)
  return exists == 1
end

_M.process = process
return _M 
