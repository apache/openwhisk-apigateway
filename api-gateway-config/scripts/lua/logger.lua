--- @module json
local logger = {}

function logger.err(s)
  ngx.log(ngx.ERR, s)
end

function logger.debug(s)
  ngx.log(ngx.DEBUG, s)
end

return logger