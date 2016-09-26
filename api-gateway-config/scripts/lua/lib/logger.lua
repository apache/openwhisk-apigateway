--- @module json
local logger = {}

function logger.err(s)
  ngx.log(ngx.ERR, s)
end

function logger.debug(s)
  print(s)
end

return logger