--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

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
    ngx.req = { get_uri_args = function() return {} end }
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey"
      }
    ]])
    red:set('snapshots:tenant:abcd', 'abcdefg')

    red:hset('snapshots:abcdefg:resources:abcd:v1/test', 'resources', '{"apiId":"bnez"}')
    red:set('snapshots:abcdefg:subscriptions:tenant:abcd:api:bnez:key:a1234', 'true')
    local dataStore = ds.initWithDriver(red)
    dataStore:setSnapshotId('abcd')
    local key = apikey.process(dataStore, securityObj, function() return "fakehash" end)
    assert.same(key, 'a1234')
  end)
  it('Checks an apiKey correctly in a query string', function()
    local red = fakeredis.new()
    local ngx = fakengx.new()

    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    local ngxattrs = cjson.decode([[
      {
        "tenant":"abcd",
        "gatewayPath":"v1/test"
      }
    ]])
    ngx.var = ngxattrs
    ngx.req = { get_uri_args = function() return { apiKey = "a1234" } end }
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey",
        "name":"apiKey",
        "location":"query"
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
    ngx.req = { get_uri_args = function() return { apiKey = "a1234" } end }
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
    ngx.req = { get_uri_args = function() return {} end}
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey",
        "name":"x-test-key"
      }
    ]])
    red:hset('resources:abcd:v1/test', 'resources', '{"apiId":"bnez"}')
    red:set('subscriptions:tenant:abcd:api:bnez:key:a1234', 'true')
    local key = apikey.process(dataStore, securityObj, function() return "fakehash" end)
    assert.same(key, 'a1234')
  end)
  it('Checks for a key with a custom name in the query string', function()
    local red = fakeredis.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    local ngx = fakengx.new()
    local ngxattrs = cjson.decode([[
      {
        "tenant":"abcd",
        "gatewayPath":"v1/test"
      }
    ]])
    ngx.var = ngxattrs
    ngx.req = { get_uri_args = function () return { xtestkey = "a1234" } end }
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey",
        "name":"xtestkey",
        "location":"query"
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
    ngx.req = { get_uri_args = function() return {} end }
    ngx.var = ngxattrs
    _G.ngx = ngx
    local securityObj = cjson.decode([[
      {
        "scope":"api",
        "type":"apikey",
        "name":"x-test-key",
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

  it('Has no cross-contamination between App ID caches', function()
    local red = fakeredis.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    local token = "test_token"
    local appid = "app"
    local ngxattrs = [[
      {
        "http_Authorization":"]] .. token .. [[",
        "tenant":"1234",
        "gatewayPath":"v1/test"
      }
    ]]
    local ngx = fakengx.new()
    ngx.config = { ngx_lua_version = 'test' }
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"oauth2",
        "provider":"app-id",
        "tenantId": "tenant1",
        "scope":"api"
      }
    ]]
    red:set('oauth:providers:appid_tenant2:tokens:test_token', '{"token":"good"}')
    red:set('oauth:providers:appid_tenant1:tokens:test_token', '{"token":"good"}')
    local result = oauth.process(dataStore, cjson.decode(securityObj))
    assert.truthy(result)
  end)

  it('Successfully fetches App ID JWK keys and validates token', function()
    local red = fakeredis.new()
    -- Mock red.expire w/ a no-op to avoid a seg fault
    red.expire = function(arg)
      return {}, nil
    end
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    local token = os.getenv("OAUTH_TEST_JWT")
    local appid = "app"
    local ngxattrs = [[
      {
        "http_Authorization":"]] .. token .. [[",
        "tenant":"1234",
        "gatewayPath":"v1/test"
      }
    ]]
    local ngx = fakengx.new()
    ngx.config = { ngx_lua_version = 'test' }
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    -- Mock http lib request to return the "right" values
    local http = require 'resty.http'
    http.request_uri = function (url, params)
      local res = {}
      res.status = 200
      res.body = os.getenv("OAUTH_TEST_JWK")
      return res, nil
    end

    local securityObj = [[
      {
        "type":"oauth2",
        "provider":"app-id",
        "tenantId": "tenant1",
        "scope":"api"
      }
    ]]
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
    ngx.req = { get_uri_args = function() return {} end }
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
  it('Validates a client secret pair with default names and snapshotting', function()
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
    ngx.req = { get_uri_args = function() return {} end }
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"clientsecret",
        "scope":"resource"
      }
    ]]
    red:set("snapshots:tenant:1234", "abcdefg")
    red:set("snapshots:abcdefg:subscriptions:tenant:1234:resource:v1/test:clientsecret:abcd:fakehash", "true")
    local ds = require 'lib/dataStore'
    local dataStore = ds.initWithDriver(red)
    dataStore:setSnapshotId("1234")
    local result = clientSecret.processWithHashFunction(dataStore, cjson.decode(securityObj), function() return "fakehash" end)
    assert(result)
  end)
  it('Doesn\'t validate a client secret pair in a different snapshot', function()
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
    ngx.req = { get_uri_args = function() return {} end }
    ngx.var = cjson.decode(ngxattrs)
    _G.ngx = ngx
    local securityObj = [[
      {
        "type":"clientsecret",
        "scope":"resource"
      }
    ]]
    red:set("snapshots:tenant:1234", "abcdefg")
    red:set("snapshots:abcdefh:subscriptions:tenant:1234:resource:v1/test:clientsecret:abcd:fakehash", "true")
    local ds = require 'lib/dataStore'
    local dataStore = ds.initWithDriver(red)
    dataStore:setSnapshotId("1234")
    local result = clientSecret.processWithHashFunction(dataStore, cjson.decode(securityObj), function() return "fakehash" end)
    assert.falsy(result)
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
    ngx.req = { get_uri_args = function() return {} end }
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
    ngx.req = { get_uri_args = function() return {} end }
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
    ngx.req = { get_uri_args = function() return {} end}
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
