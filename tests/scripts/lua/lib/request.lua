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
local request = require 'lib/request'
local cjson = require 'cjson'

describe('Testing Request module', function()
  before_each(function()
    _G.ngx = fakengx.new()
  end)

  it('should return correct error response', function()
    local code = 500
    local msg = 'Internal server error\n'
    request.err(code ,msg)
    local expected = cjson.encode{status = code, message = 'Error: ' .. msg}
    local actual = ngx._body
    assert.are.same(expected .. '\n', actual)
    assert.are.equal(code, ngx._exit)
  end)

  it('should return correct success response', function()
    local code = 200
    local msg ='Success!\n'
    request.success(code, msg)
    assert.are.equal(msg .. '\n', ngx._body)
    assert.are.equal(code, ngx._exit)
  end)
end)