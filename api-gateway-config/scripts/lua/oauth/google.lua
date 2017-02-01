---
-- A Proxy for Google OAuth API

function validateOAuthToken (token) 
  local cjson = require "cjson"
  local http = require "resty.http"
  local httpc = http.new()

  local request_options = {
    headers = {
      ["Accept"] = "application/json"
    },
    ssl_verify = false
  }
  local request_uri = "https://" .. "www.googleapis.com"  .. "/oauth2/v3/tokeninfo?access_token=" .. token
  local res, err = httpc:request_uri(request_uri, request_options)
-- convert response
  if not res then
    ngx.log(ngx.WARN, "Could not invoke Google API. Error=", err)
    ngx.print('{ "valid": false }')
    return
  end
  ngx.log(ngx.DEBUG, "Response form Google:" .. tostring(res.body))
  local json_resp = cjson.decode(res.body)
  
  if (json_resp.error_description) then
    return
  end

  -- convert Google's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  return json_resp
end

return validateOAuthToken


