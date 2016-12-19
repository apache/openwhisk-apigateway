
local utils = require "lib/utils"
local request = require "lib/request"
local cjson = require "cjson" 
local redis = require "lib/redis"


local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = os.getenv("REDIS_PORT")
local REDIS_PASS = os.getenv("REDIS_PASS")

-- Process the security object
-- @param securityObj security object from nginx conf file 
-- @return oauthId oauth identification
local _M = {}
function process(securityObj) 
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = ngx.var.apiId
  local scope = securityObj.scope

  local loaded, provider = pcall(require, utils.concatStrings({'oauth/', securityObj.provider}))
  if not loaded then 
    request.err(500, 'Error loading OAuth provider authentication module')
  end
  local token = ngx.var[utils.concatStrings({'http_', 'Authorization'}):gsub("-", "_")]

  if token == nil then
    request.err(401, "No Authorization header provided")
  end
 
  local key = utils.concatStrings({"oauth:providers:", securityObj.provider, ":tokens:", token})
  if not redis.existsOAuthToken(red, key) then
    local res = provider(token)
    if not res then
      request.err(401, "Token didn't work") 
    end
    redis.createOAuthToken(red, key, res.expires_in)
  end
  -- only check with the provider if we haven't cached the token. 
end 
_M.process = process
return _M
