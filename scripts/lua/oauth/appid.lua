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
  local keyUrl = utils.concatStrings({APPID_PKURL, '/', securityObj.tenantId, '/publickeys'})

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
  res = cjson.decode(res.body)
  local key = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAn4Tw7golPpKj+VSQIiRT
RApbtCMyn28btLu9nHQzf32J1niY/uJZZbo5O+MsekNPHu5qmLBFCS0M3HcYeKAk
OZtu7z9W1Lkronpt7WBWu+7qnGZm2vPw9rOUflZjGS5Qh9RinPJ9S5tnOrO5VapA
7Rb2Q6EU3scgsDFvVaxBERf6IuDXgwYZp+tCcmBccEDBIfQ44mvu/6dHPwAUICJw
3y/S4hqv2VEDslEdAJm2kj+WRIYooFBPVlp7371iVZtmV9cStBLW5igBvePe5ots
lU7tI2NCoSxFONjF+kGxO2S8mbBzADTBXaAE7clHorp6nRj8rIxHzD0V3+W8mp2W
1QIDAQAB
-----END PUBLIC KEY-----
]]
--  for _, v in ipairs(res.keys) do
--   key = v
--  end
--  print ('key: ' .. cjson.encode(key))
--  local jwk2pem = require('jwk2pem')
--  key = jwk2pem(key)
--  key = '\n' .. key
--  print(key)
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


