local request = require 'lib/request'
local cjson = require 'cjson'
local utils = require 'lib/utils'
local APPID_PKURL = os.getenv("APPID_PKURL")
local _M = {}
local http = require 'resty.http'

function _M.process(dataStore, token, securityObj)
  print('called process')
  local result = dataStore:getOAuthToken('appId', token)
  local jwt = require 'resty.jwt'
  local httpc = http.new()
  local json_resp
  if result ~= ngx.null then
    json_resp = cjson.decode(result)
    ngx.header['X-OIDC-Email'] = json_resp['email']
    ngx.header['X-OIDC-Sub'] = json_resp['sub']
    return json_resp
  end
  local keyUrl = utils.concatStrings({APPID_PKURL, '?tenantId=', securityObj.tenantId})

  local request_options = {
    headers = {
      ["Accept"] = "application/json"
    },
    ssl_verify = false
  }
  local res, err = httpc:request_uri(keyUrl, request_options)
  if err then
    request.err(500, 'error getting app id key: ' .. err)
  end
  local key = cjson.decode(res.body).msg
  local result = jwt:verify(key, token)
  print (cjson.encode(result))
  if not result.verified then
    request.err(401, 'AppId key signature verification failed.')
    return nil
  end
  local jwt_obj = result.payload
  print(cjson.encode(jwt_obj))
  ngx.header['X-OIDC-Email'] = jwt_obj['email']
  ngx.header['X-OIDC-Sub'] = jwt_obj['sub']
  dataStore:saveOAuthToken('appId', token, cjson.encode(result), result.exp)
  return jwt_obj
end


return _M


