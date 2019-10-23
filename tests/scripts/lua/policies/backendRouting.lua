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

local backendRouting = require 'policies/backendRouting'
local fakengx = require 'fakengx'

describe('Testing backend routing module', function()
  before_each(function()
    _G.ngx = fakengx.new()
    ngx.var.backendUrl = ''
    ngx.var.upstream = ''
    ngx.req.set_uri = function(uri)
    end
  end)

  it('should work without override', function()
    ngx.var.gatewayPath = 'hello/world'
    ngx.var.tenant = '23bc46b1-71f6-4ed5-8c54-816aa4f8c502'
    ngx.var.request_uri = '/api/' .. ngx.var.tenant .. '/' .. ngx.var.gatewayPath
    backendRouting.setRoute("https://localhost:3233/api/v1/web/guest/default/hello2.json", ngx.var.gatewayPath)
    assert.are.same(ngx.var.upstream, 'https://localhost:3233')
    assert.are.same(ngx.var.backendUrl, 'https://localhost:3233/api/v1/web/guest/default/hello2.json')
  end)

  it('should work with override', function()
    ngx.var.gatewayPath = 'hello/world'
    ngx.var.tenant = '23bc46b1-71f6-4ed5-8c54-816aa4f8c502'
    ngx.var.request_uri = '/api/' .. ngx.var.tenant .. '/' .. ngx.var.gatewayPath
    backendRouting.setRouteWithOverride("https://localhost:3233/api/v1/web/guest/default/hello2.json", ngx.var.gatewayPath,
       "http://172.0.0.1:3456")
    assert.are.same(ngx.var.upstream, 'http://172.0.0.1:3456')
    assert.are.same(ngx.var.backendUrl, 'http://172.0.0.1:3456/api/v1/web/guest/default/hello2.json')
  end)

  it('should match URI properly, ignoring API tenant base path', function()
    ngx.var.gatewayPath = 'api'
    ngx.var.tenant = '23bc46b1-71f6-4ed5-8c54-816aa4f8c502'
    ngx.var.request_uri = '/api/' .. ngx.var.tenant .. '/' .. ngx.var.gatewayPath
    actual = backendRouting.getUriPath('/api')
    assert.are.same(actual, '/api')
  end)
end)
