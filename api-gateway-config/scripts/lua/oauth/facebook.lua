local cjson = require 'cjson'
local http = require 'resty.http'
local request = require "lib/request"
local httpc = http.new()
local utils = require "lib/utils"

function validateOAuthToken (token) 

  local headerName = utils.concatStrings({'http_', 'x-facebook-app-token'}):gsub("-", "_")
  
  facebookAppToken = ngx.var[headerName] 
  if facebookAppToken == nil then
    request.err(401, 'Facebook requires you provide an app token to validate user tokens. Provide a X-Facebook-App-Token header')
  end

  local request_options = {
    headers = {
      ['Accept'] = 'application/json'
    },
    ssl_verify = false
  }
  local request_uri = 'https://' .. 'graph.facebook.com' .. '/debug_token?input_token=' .. token .. '&access_token=' .. facebookAppToken
  local res, err = httpc:request_uri(request_uri, request_options)
-- convert response
  if not res then
    ngx.log(ngx.WARN, 'Could not invoke Facebook API. Error=', err)
    ngx.print('{ \'valid\': false }')
    return
  end
  ngx.log(ngx.DEBUG, 'Response form Facebook:' .. tostring(res.body))
  local json_resp = cjson.decode(res.body)
  
  if (json_resp['error']) then
    return
  end
  -- facebook uses a different expire field than others
  json_resp['expires'] = json_resp['expires_at']
  -- convert Facebook's response
  -- Read more about the fields at: https://developers.google.com/identity/protocols/OpenIDConnect#obtainuserinfo
  return json_resp
end

return validateOAuthToken

