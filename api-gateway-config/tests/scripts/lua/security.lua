
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
    red:set('subscriptions:tenant:abcd:api:bnez:key:x-api-key:a1234', 'true')
    local key = apikey.processWithRedis(red, securityObj, function() return "fakehash" end)
    assert.same(key, 'a1234')
  end) 
  it('Returns nil with a bad apikey', function() 
    local red = fakeredis.new() 
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
    local key = apikey.processWithRedis(red, securityObj, function() return "fakehash" end)
    assert.falsy(key)
  end) 
  it('Checks for a key with a custom header', function() 
    local red = fakeredis.new() 
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
    red:set('subscriptions:tenant:abcd:api:bnez:key:x-test-key:a1234', 'true')
    local key = apikey.processWithRedis(red, securityObj, function() return "fakehash" end)
    assert.same(key, 'a1234')
  end) 
  it('Checks for a key with a custom header and hash configuration', function() 
    local red = fakeredis.new() 
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
    red:set('subscriptions:tenant:abcd:api:bnez:key:x-test-key:fakehash', 'true')
    local key = apikey.processWithRedis(red, securityObj, function() return "fakehash" end)
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
    local result = oauth.processWithRedis(red, cjson.decode(securityObj)) 
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
    local result = oauth.processWithRedis(red, cjson.decode(securityObj))
    assert.same(red:exists('oauth:providers:mock:tokens:bad'), 0)
    assert.falsy(result)
  end)
end) 
