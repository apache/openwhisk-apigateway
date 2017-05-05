
-- Copyright (c) 2016 IBM. All rights reserved.
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the "Software"),
--   to deal in the Software without restriction, including without limitation
--   the rights to use, copy, modify, merge, publish, distribute, sublicense,
--   and/or sell copies of the Software, and to permit persons to whom the
--   Software is furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in
--   all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
--   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
--   DEALINGS IN THE SOFTWARE.

local fakengx = require 'fakengx'
local fakeredis = require 'fakeredis'
local apikey = require 'policies/security/apiKey'
local oauth = require 'policies/security/oauth2'
local cjson = require "cjson"

describe('API Key module', function()
  it('Checks an apiKey correctly', function()
    local red = fakeredis.new()
    local ngx = fakengx.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red) 
    local ngxattrs = cjson.decode([[
      {
        "tenant":"abcd",
        "gatewayPath":"v1/test",
        "http_x_api_key":"a1234"
      }
    ]])
    ngx.var = ngxattrs
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey"
      }
    ]])
    red:hset('resources:abcd:v1/test', 'resources', '{"apiId":"bnez"}')
    red:set('subscriptions:tenant:abcd:api:bnez:key:a1234', 'true')
    local key = apikey.process(dataStore, securityObj, function() return "fakehash" end)
    assert.same(key, 'a1234')
  end)
  it('Returns nil with a bad apikey', function()
    local red = fakeredis.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    local ngx = fakengx.new()
    local ngxattrs = cjson.decode([[
      {
        "tenant":"abcd",
        "gatewayPath":"v1/test",
        "http_x_api_key":"a1234"
      }
    ]])
    ngx.var = ngxattrs
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey"
      }
    ]])
    red:hset('resources:abcd:v1/test', 'resources', '{"apiId":"bnez"}')
    local key = apikey.process(dataStore, securityObj, function() return "fakehash" end)
    assert.falsy(key)
  end)
  it('Checks for a key with a custom header', function()
    local red = fakeredis.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    local ngx = fakengx.new()
    local ngxattrs = cjson.decode([[
      {
        "tenant":"abcd",
        "gatewayPath":"v1/test",
        "http_x_test_key":"a1234"
      }
    ]])
    ngx.var = ngxattrs
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey",
        "header":"x-test-key"
      }
    ]])
    red:hset('resources:abcd:v1/test', 'resources', '{"apiId":"bnez"}')
    red:set('subscriptions:tenant:abcd:api:bnez:key:a1234', 'true')
    local key = apikey.process(dataStore, securityObj, function() return "fakehash" end)
    assert.same(key, 'a1234')
  end)
  it('Checks for a key with a custom header and hash configuration', function()
    local red = fakeredis.new()
    local ds = require "lib/dataStore" 
    local dataStore = ds.initWithDriver(red) 
    local ngx = fakengx.new()
    local ngxattrs = cjson.decode([[
      {
        "tenant":"abcd",
        "gatewayPath":"v1/test",
        "http_x_test_key":"a1234"
      }
    ]])
    ngx.var = ngxattrs
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey",
        "header":"x-test-key",
        "hashed":true
      }
    ]])
    red:hset('resources:abcd:v1/test', 'resources', '{"apiId":"bnez"}')
    red:set('subscriptions:tenant:abcd:api:bnez:key:fakehash', 'true')
    local key = apikey.processWithHashFunction(dataStore, securityObj, function() return "fakehash" end)
    assert.same(key, 'fakehash')
  end)
end)
describe('OAuth security module', function()
  it('Exchanges a good secret', function ()
    local red = fakeredis.new()
    local token = "test"
    local ngxattrs = [[
      {
        "http_Authorization":"]] .. token .. [[",
        "tenant":"1234",
        "gatewayPath":"v1/test"
      }
    ]]
    local ngx = fakengx.new()
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"oauth",
        "provider":"mock",
        "scope":"resource"
      }
    ]]
    local result = oauth.process(red, cjson.decode(securityObj))
    assert.same(red:exists('oauth:providers:mock:tokens:test'), 1)
    assert(result)
  end)
  it('Exchanges a bad token, doesn\'t cache it and returns false', function()
    local red = fakeredis.new()  
    local token = "bad"
    local ngxattrs = [[
      {
        "http_Authorization":"]] .. token .. [[",
        "tenant":"1234",
        "gatewayPath":"v1/test"
      }
    ]]
    local ngx = fakengx.new()
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"oauth",
        "provider":"mock",
        "scope":"resource"
      }
    ]]
    local result = oauth.process(red, cjson.decode(securityObj))
    assert.same(red:exists('oauth:providers:mock:tokens:bad'), 0)
    assert.falsy(result)
  end)
  it('Loads a facebook token from the cache without a valid app id', function()
    local red = fakeredis.new()
    local ds = require "lib/dataStore" 
    local dataStore = ds.initWithDriver(red)
    local token = "test"
    local ngxattrs = [[
      {
        "http_Authorization":"]] .. token .. [[",
        "http_x_facebook_app_token":"nothing",
        "tenant":"1234",
        "gatewayPath":"v1/test"
      }
    ]]
    local ngx = fakengx.new()
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"oauth2",
        "provider":"facebook",
        "scope":"resource"
      }
    ]]
    red:set('oauth:providers:facebook:tokens:test', '{ "token":"good"}')
    local result = oauth.process(dataStore, cjson.decode(securityObj))
    assert.truthy(result)
  end)
  it('Loads a facebook token from the cache with a valid app id', function()
    local red = fakeredis.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    local token = "test"
    local appid = "app"
    local ngxattrs = [[
      {
        "http_Authorization":"]] .. token .. [[",
        "http_x_facebook_app_token":"]] .. appid .. [[",
        "tenant":"1234",
        "gatewayPath":"v1/test"
      }
    ]]
    local ngx = fakengx.new()
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"oauth2",
        "provider":"facebook",
        "scope":"resource"
      }
    ]]
    red:set('oauth:providers:facebook:tokens:testapp', '{"token":"good"}')
    local result = oauth.process(dataStore, cjson.decode(securityObj))
    assert.truthy(result)
  end)
end)
describe('Client Secret Module', function()
  local clientSecret = require 'policies/security/clientSecret'
  it('Validates a client secret pair with default names', function()
    local ngx = fakengx.new()
    local red = fakeredis.new()
    local ngxattrs = [[
      {
       "http_X_Client_ID":"abcd",
       "http_X_Client_Secret":"1234",
       "tenant":"1234",
       "gatewayPath":"v1/test"
      }
    ]]
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"clientsecret",
        "scope":"resource"
      }
    ]]
    red:set("subscriptions:tenant:1234:resource:v1/test:clientsecret:abcd:fakehash", "true")
    local result = clientSecret.processWithHashFunction(red, cjson.decode(securityObj), function() return "fakehash" end)
    assert(result)
  end)
  it('Validates a client secret pair with new names', function()
    local ngx = fakengx.new()
    local red = fakeredis.new()
    local ngxattrs = [[
      {
        "http_test_id":"abcd",
        "http_test_secret":"1234",
        "tenant":"1234",
        "gatewayPath":"v1/test"
      }
    ]]
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"clientsecret",
        "scope":"resource",
        "idFieldName":"test-id",
        "secretFieldName":"test-secret"
      }
    ]]
    red:set("subscriptions:tenant:1234:resource:v1/test:clientsecret:abcd:fakehash", "true")
    local result = clientSecret.processWithHashFunction(red, cjson.decode(securityObj), function() return "fakehash" end)
    assert(result)
  end)
  it('Doesn\'t work without a client id', function()
    local ngx = fakengx.new()
    local red = fakeredis.new()
    local ngxattrs = [[
      {
       "http_X_Client_Secret":"1234",
       "tenant":"1234",
       "gatewayPath":"v1/test"
      }
    ]]
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"clientsecret",
        "scope":"resource"
      }
    ]]
  end)
  it('Doesn\'t work without a Client Secret', function()
    local ngx = fakengx.new()
    local red = fakeredis.new()
    local ngxattrs = [[
      {
       "http_X_Client_ID":"abcd",
       "tenant":"1234",
       "gatewayPath":"v1/test"
      }
    ]]
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"clientsecret",
        "scope":"resource"
      }
    ]]
    red:set("subscriptions:tenant:1234:resource:v1/test:clientsecret:abcd:fakehash", "true")
    local result = clientSecret.processWithHashFunction(red, cjson.decode(securityObj), function() return "fakehash" end)
    assert.falsy(result)
  end)
end)
