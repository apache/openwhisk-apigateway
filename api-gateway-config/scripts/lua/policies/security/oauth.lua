
local utils = require "lib/utils"
local request = require "lib/request"
local cjson = require "cjson" 
local redis = require "lib/redis"
ngx.log(ngx.DEBUG, 'redis loaded correctly.')


local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

-- Process the security object
-- @param securityObj security object from nginx conf file 
-- @return oauthId oauth identification
local _M = {}
function process(securityObj, skipValidation) 
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = ngx.var.apiId
  local scope = securityObj.scope
  local token = nil

  local loaded, provider = pcall(require, utils.concatStrings({'oauth/', securityObj.provider}))
  if not loaded then 
    request.err(500, 'Error loading OAuth provider authentication module')
  end
  local accessToken = ngx.var[utils.concatStrings({'http_', 'Authorization'}):gsub("-", "_")]

  if accessToken == nil then
    request.err(401, "No Authorization header provided")
  end
 
  local key = utils.concatStrings({"oauth:providers:", securityObj.provider, ":tokens:", accessToken})
  if not redis.existsOAuthToken(red, key) then
    token = provider(accessToken)
    if not token or not token.email then
      request.err(401, "Token didn't work or provider doesn't support OpenID connect.") 
    end
    redis.createOAuthToken(red, key, token) 
  else 
    token = cjson.decode(red:get(key))
  end
  if not skipValidation and not validate(tenant, gatewayPath, apiId, scope, token.email) then
    request.err(401, "You are not subscribed to this API") 
  end
  return token
-- only check with the provider if we haven't cached the token. 
end


function validate (tenant, gatewayPath, apiId, scope, userId) 
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  if scope == 'tenant' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant})
  elseif scope == 'resource' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':resource:', gatewayPath})
  elseif scope == 'api' then
    k = utils.concatStrings({'subscriptions:tenant:', tenant, ':api:', apiId})
  end
  k = utils.concatStrings({k, ':key:', userId})
  ngx.log(ngx.DEBUG, k)
  if red:exists(k) == 1 then
    return true
  else 
    return false
  end
end 

_M.process = process
return _M
