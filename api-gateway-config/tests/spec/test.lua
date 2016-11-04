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

-- Unit tests for the apigateway using the busted framework.
-- @author Alex Song (songs)

local fakengx = require 'fakengx'
local fakeredis = require 'fakeredis'
local cjson = require 'cjson'
local request = require 'lib/request'
local utils = require 'lib/utils'
local logger = require 'lib/logger'
local redis = require 'lib/redis'
local mapping = require 'policies/mapping'


------------------------------------
---- Unit tests for lib modules ----
------------------------------------

describe('Testing Request module', function()
  before_each(function()
    _G.ngx = fakengx.new()
  end)

  it('should return correct error response', function()
    local code = 500
    local msg = 'Internal server error\n'
    request.err(code, msg)
    assert.are.equal(ngx._body, 'Error: ' .. msg)
    assert.are.equal(ngx._exit, code)
  end)

  it('should return correct success response', function()
    local code = 200
    local msg ='Success!\n'
    request.success(code, msg)
    assert.are.equal(ngx._body, msg)
    assert.are.equal(ngx._exit, code)
  end)
end)


describe('Testing utils module', function()
  before_each(function()
    _G.ngx = fakengx.new()
  end)

  it('should concatenate strings properly', function()
    local expected = 'hello' .. 'gateway' .. 'world'
    local generated = utils.concatStrings({'hello', 'gateway', 'world'})
    assert.are.equal(expected, generated)
  end)

  it('should serialize lua table', function()
    -- Empty table
    local expected = {}
    local serialized = utils.serializeTable(expected)
    loadstring('generated = ' .. serialized)() -- convert serialzed string to lua table
    assert.are.same(expected, generated)

    -- Simple table
    expected = {
      test = true
    }
    serialized = utils.serializeTable(expected)
    loadstring('generated = ' .. serialized)() -- convert serialzed string to lua table
    assert.are.same(expected, generated)

    -- Complex nested table
    expected = {
      test1 = {
        nested = 'value'
      },
      test2 = true
    }
    serialized = utils.serializeTable(expected)
    loadstring('generated = ' .. serialized)() -- convert serialzed string to lua table
    assert.are.same(expected, generated)
  end)

  it('should convert templated path parameter', function()
    -- TODO: Add test cases for convertTemplatedPathParam(m)
  end)
end)


describe('Testing logger module', function()
  it('Should handle error stream', function()
    local msg = 'Error!'
    logger.err(msg)
    local expected = 'LOG(4): ' .. msg .. '\n'
    local generated = ngx._log
    assert.are.equal(expected, generated)
  end)
end)


describe('Testing Redis module', function()
  before_each(function()
    _G.ngx = fakengx.new()
    red = fakeredis.new()
  end)

  it('should generate resource object to store in redis', function()
    -- Resource object with no policies or security
    local key = 'resources:guest:hello'
    local gatewayMethod = 'GET'
    local backendUrl = 'https://httpbin.org/get'
    local backendMethod = gatewayMethod
    local apiId = 12345
    local policies
    local security
    local resourceObj = {
      operations = {
        [gatewayMethod] = {
          backendUrl = backendUrl,
          backendMethod = backendMethod
        }
      },
      apiId = apiId
    }
    local expected = resourceObj
    local generated = cjson.decode(redis.generateResourceObj(red, key, gatewayMethod, backendUrl, backendMethod, apiId, policies, security))
    assert.are.same(expected, generated)

    -- Resource object with policy added
    local policyList = [[
      [{
          "type":"rateLimit",
          "value":[{
              "interval":60,
              "rate":100,
              "scope":"api",
              "subscription": "true"
          }]
      }]
    ]]
    policies = cjson.decode(policyList)
    resourceObj.operations[gatewayMethod].policies = policies
    expected = resourceObj
    generated = cjson.decode(redis.generateResourceObj(red, key, gatewayMethod, backendUrl, backendMethod, apiId, policies, security))
    assert.are.same(expected, generated)

    -- Resource object with security added
    local securityObj = [[
      {
        "type":"apiKey",
        "scope":"api",
        "header":"myheader"
      }
    ]]
    security = cjson.decode(securityObj)
    resourceObj.operations[gatewayMethod].security = security
    expected = resourceObj
    generated = cjson.decode(redis.generateResourceObj(red, key, gatewayMethod, backendUrl, backendMethod, apiId, policies, security))
    assert.are.same(expected, generated)

    -- Update already existing resource object
    local field = 'resources'
    redis.createResource(red, key, field, cjson.encode(generated))
    local newGatewayMethod = 'POST'
    resourceObj.operations[newGatewayMethod] = {
      backendUrl = backendUrl,
      backendMethod = backendMethod
    }
    policies = nil
    security = nil
    expected = resourceObj
    generated = cjson.decode(redis.generateResourceObj(red, key, newGatewayMethod, backendUrl, backendMethod, apiId, policies, security))
    assert.are.same(expected, generated)
  end)

  it('should get a resource from redis', function()
    local key = 'resources:guest:hello'
    local field = 'resources'
    -- resource doesn't exist in redis
    local generated = redis.getResource(red, key, field)
    assert.are.same(nil, generated)

    -- resource exists in redis
    local expected = redis.generateResourceObj(red, key, 'GET', 'https://httpbin.org/get', 'GET', '12345', nil, nil)
    red:hset(key, field, expected)
    generated = redis.getResource(red, key, field)
    assert.are.same(expected, generated)
  end)

  it('should create a resource in redis', function()
    local key = 'resources:guest:hello'
    local field = 'resources'
    local expected = redis.generateResourceObj(red, key, 'GET', 'https://httpbin.org/get', 'GET', '12345', nil, nil)
    redis.createResource(red, key, field, expected)
    local generated = redis.getResource(red, key, field)
    assert.are.same(expected, generated)
  end)

  it('should delete a resource in redis', function()
    -- Key doesn't exist - throw 404
    local key = 'resources:guest:hello'
    local field = 'resources'
    redis.deleteResource(red, key, field)
    assert.are.equal(ngx._exit, 404)
    -- Key exists - deleted properly
    local resourceObj = redis.generateResourceObj(red, key, 'GET', 'https://httpbin.org/get', 'GET', '12345', nil, nil)
    redis.createResource(red, key, field, resourceObj)
    local expected = 1
    local generated = redis.deleteResource(red, key, field)
    assert.are.same(expected, generated)
  end)

  it('shoud create an API Key subscription', function()
    local key = 'subscriptions:test:apikey'
    redis.createSubscription(red, key)
    assert.are.same(true, red:exists(key))
  end)

  it('should delete an API Key subscription', function()
    -- API key doesn't exist in redis - throw 404
    local key = 'subscriptions:test:apikey'
    redis.deleteSubscription(red, key)
    assert.are.equal(404, ngx._exit)

    -- API key to delete exists in redis
    red:set(key, '')
    redis.deleteSubscription(red, key)
    assert.are.equal(false, red:exists(key))
  end)
end)

--TODO: filemgmt

---------------------------------------
---- Unit tests for policy modules ----
---------------------------------------

--TODO: mapping, rateLimit, security
describe('Testing mapping module', function()
  before_each(function()
    _G.ngx = fakengx.new()
  end)
end)
