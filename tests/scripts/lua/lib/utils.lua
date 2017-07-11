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
local utils = require 'lib/utils'

describe('Testing utils module', function()
  before_each(function()
    _G.ngx = fakengx.new()
  end)

  it('should concatenate strings properly', function()
    local expected = 'hello' .. 'gateway' .. 'world'
    local generated = utils.concatStrings({'hello', 'gateway', 'world'})
    assert.are.equal(expected, generated)
  end)

  it('should serialize a simple lua table', function()
    local expected = {
      test = true
    }
    local serialized = utils.serializeTable(expected)
    loadstring('generated = ' .. serialized)() -- convert serialzed string to lua table
    assert.are.same(expected, generated)
  end)

  it('should serialize an empty table', function()
    local expected = {}
    local serialized = utils.serializeTable(expected)
    loadstring('generated = ' .. serialized)() -- convert serialzed string to lua table
    assert.are.same(expected, generated)
  end)

  it('should serialize complex nested table', function()
    local expected = {
      test1 = {
        nested = 'value'
      },
      test2 = true
    }
    local serialized = utils.serializeTable(expected)
    loadstring('generated = ' .. serialized)() -- convert serialzed string to lua table
    assert.are.same(expected, generated)
  end)
end)