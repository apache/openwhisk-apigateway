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
local cjson = require 'cjson'
local redis = require 'lib/redis'

describe('Testing Redis module', function()
  before_each(function()
    _G.ngx = fakengx.new()
    red = fakeredis.new()
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
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
    local dataStore = ds.initWithDriver(red)
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
    local dataStore = ds.initWithDriver(red)
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
    local dataStore = ds.initWithDriver(red)
    -- resource doesn't exist in redis
    local generated = dataStore:getResource(key, field)
    assert.are.same(nil, generated)

    -- resource exists in redis
    local expected = dataStore:generateResourceObj(operations, nil)
    red:hset(key, field, expected)
    local dataStore = ds.initWithDriver(red)
    generated = dataStore:getResource(key, field)
    assert.are.same(expected, generated)
  end)

  it('should create a resource in redis', function()
    local key = 'resources:guest:hello'
    local field = 'resources'
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
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
    local dataStore = ds.initWithDriver(red)
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
    local dataStore = ds.initWithDriver(red)
    dataStore:createSubscription(key)
    assert.are.same(1, red:exists(key))
  end)

  it('should delete an API Key subscription', function()
    -- API key doesn't exist in redis - throw 404
    local key = 'subscriptions:test:apikey'
    local ds = require "lib/dataStore"
    local dataStore = ds.initWithDriver(red)
    dataStore:deleteSubscription(key)
    assert.are.equal(404, ngx._exit)

    -- API key to delete exists in redis
    red:set(key, '')
    dataStore:deleteSubscription(key)
    assert.are.equal(0, red:exists(key))
  end)

end)
