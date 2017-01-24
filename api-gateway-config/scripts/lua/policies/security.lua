local _M = {}

local utils = require "lib/utils"

function process(securityObj)
  local ok, result = pcall(require, utils.concatStrings({'policies/security/', securityObj.type}))
  if not ok then
    ngx.err(500, 'An unexpected error ocurred while processing the security policy') 
  end 
  
  local red = redis.init(REDIS_HOST, REDIS_PORT, REDIS_PASS, 1000)
  local tenant = ngx.var.tenant
  local gatewayPath = ngx.var.gatewayPath
  local apiId = ngx.var.apiId
  local scope = securityObj.scope
  local apiKey = ngx.var[utils.concatStrings({'http_', header}):gsub("-", "_")]
 
  result.process(red, tenant, gatewayPath, apiId, scope, apiKey, securityObj)
end

_M.process = process

return _M 
