
local utils = require "lib/utils"
local request = require "lib/request"
local redis = require "lib/redis"
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
  
  local accessToken = ngx.var['http_Authorization']
  if accessToken == nil then
    request.err(401, "No Authorization header provided")
  end
  local token = {}
  local key = utils.concatStrings({"oauth:providers:", securityObj.provider, ":tokens:", accessToken})
  if not (red:exists(key) == 1) then
    token = exchange(red, accessToken, securityObj.provider)
  else 
    token = cjson.decode(red:get(key))
  end

  if token == nil then
    request.err(401, "Token didn't work or provider doesn't support OpenID connect.") 
    return
  end
 
  red:set(key, cjson.encode(token))
  
  if not token.expires == nil then
    red:expire(key, token.expires)
  end
  
  return token
-- only check with the provider if we haven't cached the token. 
end

function exchange(red, token, provider) 
    local loaded, provider = pcall(require, utils.concatStrings({'oauth/', provider}))
    
    if not loaded then 
      request.err(500, 'Error loading OAuth provider authentication module')
      return 
    end

    local token = provider(token)
    -- cache the token
    return token
end

_M.process = process
return _M
