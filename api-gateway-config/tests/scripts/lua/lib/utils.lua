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