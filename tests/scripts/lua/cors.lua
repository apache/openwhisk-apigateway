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
local cors = require 'cors'
local redis = require 'lib/redis'
local cjson = require 'cjson'


describe('Testing cors headers', function()
  before_each(function()
    _G.ngx = fakengx.new()
    ngx.var.cors_origins = ''
    ngx.var.cors_methods = ''
    operations = {
      GET = {
        backendUrl = 'https://example.com',
        backendMethod = 'GET'
      }
    }
    _G.resourceObj = cjson.decode(redis.generateResourceObj(operations, nil, nil, nil))
  end)

  it('Access-Control headers should be present for preflight options call if cors is enabled', function()
    -- mock options call
    ngx.req.get_method = function()
      return 'OPTIONS'
    end

    ngx.header['Access-Control-Request-Headers'] = 'test-header'

    resourceObj.cors = {
      origin = 'true',
      methods = 'GET, POST, PUT'
    }
    cors.processCall(resourceObj)
    cors.replaceHeaders()

    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Origin'], '*')
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Methods'], 'GET, POST, PUT')
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Credentials'], 'true')
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Headers'], 'test-header')
  end)

  it('Access-Control headers should be present with cors enabled', function()
    resourceObj.cors = {
      origin = 'true',
    }
    cors.processCall(resourceObj)
    cors.replaceHeaders()

    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Origin'], '*')
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Methods'], 'GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS')
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Credentials'], 'true')
  end)

  it('Access-Control headers should not be present with cors disabled', function()
    resourceObj.cors = {
      origin = 'false'
    }
    cors.processCall(resourceObj)
    cors.replaceHeaders()

    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Origin'], nil)
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Methods'], nil)
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Headers'], nil)
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Credentials'], nil)
  end)

  it('Should pass through Access-Control headers if cors is not defined', function()
    ngx.header['Access-Control-Allow-Origin'] = 'https://foo.bar'
    ngx.header['Access-Control-Allow-Headers'] = 'Content-Type'

    resourceObj.cors = nil

    cors.processCall(resourceObj)
    cors.replaceHeaders()

    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Origin'], 'https://foo.bar')
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Headers'], 'Content-Type')
    assert.are.same(ngx.req.get_headers()['Access-Control-Allow-Methods'], nil)
  end)

end)
