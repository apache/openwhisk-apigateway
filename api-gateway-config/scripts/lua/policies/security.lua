local _M = {}

local utils = require "lib/utils"

function process(securityObj)
  local ok, result = pcall(require, utils.concatStrings({'policies/security/', securityObj.type}))
  if not ok then
    ngx.err(500, 'An unexpected error ocurred while processing the security policy') 
  end 
  result.process(securityObj)
end

_M.process = process

return _M 
