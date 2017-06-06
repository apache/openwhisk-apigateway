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
local cjson = require 'cjson'
local redis = require 'lib/redis'

describe('Testing Redis module', function()
  before_each(function()
    _G.ngx = fakengx.new()
    red = fakeredis.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    operations = {
      GET = {
        backendUrl = 'https://httpbin.org/get',
        backendMethod = 'GET'
      }
    }
  end)
  it('should look up an api by one of it\'s member resources', function() 
    local red = fakeredis.new() 
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    local sampleResource = cjson.decode([[
      {
        "apiId": "a12341234",
        "operations": {
          "GET": {
            "backendUrl":"sample",
            "backendMethod":"GET"
          }
        }
      }
    ]])
    
    red:hset('resources:test:v1/test', 'resources', cjson.encode(sampleResource))
    assert.are.same('a12341234', dataStore:resourceToApi('resources:test:v1/test'))
  end) 
  it('should generate resource object to store in redis', function()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    -- Resource object with no policies or security
    local apiId = 12345
    local resourceObj = {
      apiId = apiId,
      operations = operations
    }
    local expected = resourceObj
    local generated = cjson.decode(dataStore:generateResourceObj(operations, apiId))
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
    resourceObj.operations.GET.policies = cjson.decode(policyList)
    expected = resourceObj
    generated = cjson.decode(dataStore:generateResourceObj(operations, apiId))
    assert.are.same(expected, generated)

    -- Resource object with security added
    local securityObj = [[
      {
        "type":"apiKey",
        "scope":"api",
        "header":"myheader"
      }
    ]]
    resourceObj.operations.GET.security = cjson.decode(securityObj)
    expected = resourceObj
    generated = cjson.decode(dataStore:generateResourceObj(operations, apiId))
    assert.are.same(expected, generated)

    -- Resource object with multiple operations
    resourceObj.operations.PUT = {
      backendUrl = 'https://httpbin.org/get',
      backendMethod = 'PUT',
      security = {}
    }
    expected = resourceObj
    generated = cjson.decode(dataStore:generateResourceObj(operations, apiId))
    assert.are.same(expected, generated)

    local tenantObj = [[
      {
        "id": "123",
        "namespace": "testname",
        "instance": "testinstance"
      }
    ]]
    tenantObj = cjson.decode(tenantObj)
    resourceObj.tenantId = tenantObj.id
    resourceObj.tenantNamespace = tenantObj.namespace
    resourceObj.tenantInstance = tenantObj.instance
    expected = resourceObj
    generated = cjson.decode(dataStore:generateResourceObj(operations, apiId, tenantObj))
    assert.are.same(expected, generated)
  end)

  it('should get a resource from redis', function()
    local key = 'resources:guest:hello'
    local field = 'resources'
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    -- resource doesn't exist in redis
    local generated = dataStore:getResource(key, field)
    assert.are.same(nil, generated)

    -- resource exists in redis
    local expected = dataStore:generateResourceObj(operations, nil)
    red:hset(key, field, expected)
    local dataStore = ds.initWithDriver(red, 'redis')
    generated = dataStore:getResource(key, field)
    assert.are.same(expected, generated)
  end)

  it('should create a resource in redis', function()
    local key = 'resources:guest:hello'
    local field = 'resources'
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    local expected = dataStore:generateResourceObj(operations, nil)
    dataStore:createResource(key, field, expected)
    local generated = dataStore:getResource(key, field)
    assert.are.same(expected, generated)
  end)

  it('should delete a resource in redis', function()
    -- Key doesn't exist - throw 404
    local key = 'resources:guest:hello'
    local field = 'resources'
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    dataStore:deleteResource(key, field)
    assert.are.equal(ngx._exit, 404)
    -- Key exists - deleted properly
    local resourceObj = redis.generateResourceObj(operations, nil)
    dataStore:createResource(key, field, resourceObj)
    local expected = 1
    local generated = dataStore:deleteResource(key, field)
    assert.are.same(expected, generated)
  end)

  it('shoud create an API Key subscription', function()
    local key = 'subscriptions:test:apikey'
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    dataStore:createSubscription(key)
    assert.are.same(1, red:exists(key))
  end)

  it('should delete an API Key subscription', function()
    -- API key doesn't exist in redis - throw 404
    local key = 'subscriptions:test:apikey'
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red, 'redis')
    dataStore:deleteSubscription(key)
    assert.are.equal(404, ngx._exit)

    -- API key to delete exists in redis
    red:set(key, '')
    dataStore:deleteSubscription(key)
    assert.are.equal(0, red:exists(key))
  end)

end)
