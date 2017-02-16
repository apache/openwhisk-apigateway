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
local redis = require 'lib/redis'
local routing = require 'routing'

describe('Testing routing module', function()
  before_each(function()
    _G.ngx = fakengx.new()
    ngx.var.gatewayPath = ''
    red = fakeredis.new()
    operations = {
      GET = {
        backendUrl = 'https://httpbin.org',
        backendMethod = 'GET'
      }
    }
    keys = {'resources:guest:bp1/test/hello', 'resources:guest:bp2/hello', 'resources:guest:bp3/testing/test/hi',
      'resources:guest:bp4/another/hello', 'resources:guest:nobp', 'resources:guest:noresource/'}
    local field = 'resources'
    for _, key in pairs(keys) do
      red:hset(key, field, redis.generateResourceObj(operations, nil))
    end
  end)

  it('should find the correct redis key', function()
    local expected = 'resources:guest:bp1/test/hello'
    local tenant = 'guest'
    local path = 'bp1/test/hello'
    local actual = routing.findRedisKey(keys, tenant, path)
    assert.are.same(expected, actual)
    expected = 'bp1/test/hello'
    actual = ngx.var.gatewayPath
    assert.are.same(expected, actual)
  end)

  it('should return nil if redis key doesn\'t exist', function()
    local expected = nil
    local tenant = 'guest'
    local path = 'bp1/bad/path'
    local actual = routing.findRedisKey(keys, tenant, path)
    assert.are.same(expected, actual)
  end)

  it('should find correct key when basePath is "/"', function()
    local expected = 'resources:guest:nobp'
    local tenant = 'guest'
    local path = 'nobp'
    local actual = routing.findRedisKey(keys, tenant, path)
    assert.are.same(expected, actual)
    expected = 'nobp'
    actual = ngx.var.gatewayPath
    assert.are.same(expected, actual)
  end)

  it('should find correct key when resourcePath is "/"', function()
    local expected = 'resources:guest:noresource/'
    local tenant = 'guest'
    local path = 'noresource/'
    local actual = routing.findRedisKey(keys, tenant, path)
    assert.are.same(expected, actual)
    expected = 'noresource/'
    actual = ngx.var.gatewayPath
    assert.are.same(expected, actual)
  end)

  it('should match the correct path parameters', function()
    local key = 'resources:guest:bp5/{pathVar}'
    local redisKey = 'resources:guest:bp5/test'
    local actual = routing.pathParamMatch(key, redisKey)
    local expected = true
    assert.are.same(expected, actual)
    expected = 'test'
    actual = ngx.ctx.pathVar
    assert.are.same(expected, actual)
  end)

  it('should return false if there isn\'t a path parameter match', function()
    local key = 'resources:guest:bp6/{pathVar}/hey'
    local redisKey = 'resources:guest:bp6/test/hi'
    local actual = routing.pathParamMatch(key, redisKey)
    local expected = false
    assert.are.same(expected, actual)
    expected = nil
    actual = ngx.ctx.pathVar
    assert.are.same(expected, actual)
  end)

  it('should match multiple path parameters', function()
    local key = 'resources:guest:base/{var1}/hello/{var2}'
    local redisKey = 'resources:guest:base/test/hello/testing'
    local actual = routing.pathParamMatch(key, redisKey)
    local expected = true
    assert.are.same(expected, actual)
    expected = 'test'
    actual = ngx.ctx.var1
    assert.are.same(expected, actual)
    expected = 'testing'
    actual = ngx.ctx.var2
    assert.are.same(expected, actual)
  end)

end)
