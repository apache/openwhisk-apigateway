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

package.path = package.path .. ';/usr/local/share/lua/5.2/?.lua' ..
    ';/usr/local/api-gateway/lualib/resty/?.lua;/etc/api-gateway/scripts/lua/?.lua'
package.cpath = package.cpath .. ';/usr/local/lib/lua/5.2/?.so;/usr/local/api-gateway/lualib/?.so'

local fakengx = require 'fakengx'
local request = require 'lib/request'

describe('Testing Request module', function()
  before_each(function()
    -- Mock ngx object for each test
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
