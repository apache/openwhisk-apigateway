local routing = {}
local mapping = require "mapping"
local logger = require "lib/logger"
local url = require "lib/url"
local cjson = require "cjson"


function routing.processCall(obj)
  local verb = ngx.req.get_method()
  local found = false
  for k, v in pairs(obj) do
    if k == verb then
      logger.debug( 'found verb: ' .. k)
      logger.debug( 'found backendUrl: ' .. v.backendUrl)
      local u = url.parse(v.backendUrl)
      ngx.req.set_uri(u.path)
      ngx.var.upstream = u.scheme .. '://' .. u.host
      logger.debug('upstream: ' .. ngx.var.upstream)
      if v.backendMethod ~= nil then
        logger.debug('Setting a backend method: ' .. v.backendMethod)
        setVerb(v.backendMethod)
      end
      parsePolicies(v.policies)
      found = true
      break
    else
      logger.debug( 'verb not found: ' .. k)
    end
  end
  if found == false then
    logger.debug( 'Finished loop without finding.')
    ngx.say("Whoops. Verb not supported.")
    ngx.exit(404)
  end
end

function parsePolicies(obj)
  for k, v in pairs (obj) do
    if v.type == 'reqMapping' then
      logger.debug('Found a request mapping')
      mapping.processMap(v.value)
    end
  end
end

function setVerb(v)
  if (string.lower(v) == "post") then
    ngx.req.set_method(ngx.HTTP_POST)
  elseif (string.lower(v) == "put") then
    ngx.req.set_method(ngx.HTTP_PUT)
  elseif (string.lower(v) == "delete") then
    ngx.req.set_method(ngx.HTTP_DELETE)
  else
    ngx.req.set_method(ngx.HTTP_GET)
  end
end

return routing