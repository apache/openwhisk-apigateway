--- @module whisk
local whisk = {}

local logger = require("logger")

function whisk.preprocess()
  whisk.addHeader("Content-Type", "application/json")
  whisk.setVerb("post")
  ngx.req.set_uri_args({ blocking = "true", result = "true"})
end

function whisk.addHeader(k, v)
  ngx.req.set_header(k, v)
end

function whisk.setVerb(v)
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

return whisk