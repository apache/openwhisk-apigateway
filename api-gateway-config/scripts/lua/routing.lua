local routing = {}
local json = require("json")
local mapping = require("mapping")
local logger = require("logger")


function routing.processCall(obj)
  local verb = ngx.req.get_method()
  local map = json.convertJSONObj(obj)
  local found = false
  for k, v in pairs(map) do
    if k == verb then
      logger.debug( 'found verb: ' .. k)
      ngx.req.set_uri(v.targetPath)
      ngx.var.upstream = v.targetHost
      logger.debug('upstream: ' .. ngx.var.upstream)
      found = true
      mapping.processMap(v.reqMapping)
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

return routing