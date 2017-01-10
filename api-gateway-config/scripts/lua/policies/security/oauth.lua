
local redis = require "lib/redis"
local utils = require "lib/utils"
local request = require "lib/request"
local cjson = require "cjson" 

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


  local provider = require(utils.concatStrings({'oauth/', securityObj.provider}))
  local token = ngx.var[utils.concatStrings({'http_', 'Authorization'}):gsub("-", "_")]

  if token == nil then
    request.err(401, "No Authorization header provided")
  end
 
  local key = utils.concatStrings({"oauth:providers:", securityObj.provider, ":tokens:", token})
  ngx.log(ngx.DEBUG, "key: ", key)
  if red:exists(key) == 0 then
    local res = provider(token)
    if not res then
      request.err(401, "Token didn't work") 
    end
    red:set(key, cjson.encode(res))
    ngx.log(ngx.DEBUG, "expires in: ", res.expires_in)
    red:expire(key, res.expires_in)
  end
  -- only check with the provider if we haven't cached the token. 
end 
_M.process = process
return _M
