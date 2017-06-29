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

local cjson = require "cjson"
local fakengx = require "fakengx"
local fakeredis = require "fakeredis"
local subscriptions = require "management/lib/subscriptions"
local utils = require "lib/utils"

describe("Testing v2 subscriptions API", function()
  before_each(function()
    _G.ngx = fakengx.new()
    red = fakeredis.new()
  end)

  it("should create a new subscription", function()
    -- client id only
    local artifactId = "abc"
    local tenantId = "testtenant"
    local clientId = "xxx"
    local ds = require 'lib/dataStore'
    local dataStore = ds.initWithDriver(red)
    subscriptions.addSubscription(dataStore, artifactId, tenantId, clientId)
    local generated = red:exists("subscriptions:tenant:" .. tenantId .. ":api:" .. artifactId .. ":key:" .. clientId)
    assert.are.equal(1, generated)
    -- client id and secret
    local newClientId = "newclientid"
    local clientSecret = "secret"
    subscriptions.addSubscription(dataStore, artifactId, tenantId, newClientId, clientSecret, generateHash)
    generated = red:exists("subscriptions:tenant:" .. tenantId .. ":api:" .. artifactId .. ":clientsecret:" .. newClientId .. ":" .. generateHash(clientSecret))
    assert.are.equal(1, generated)
    -- wrong secret
    local badsecret = "badsecret"
    generated = red:exists("subscriptions:tenant:" .. tenantId .. ":api:" .. artifactId .. ":clientsecret:" .. newClientId .. ":" .. generateHash(badsecret))
    assert.are.equal(0, generated)
  end)

  it("should delete a subscription", function()
    local artifactId = "abc"
    local tenantId = "testtenant"
    local clientId = "12345"
    local ds = require 'lib/dataStore'
    local dataStore = ds.initWithDriver(red)
    subscriptions.addSubscription(dataStore, artifactId, tenantId, clientId)
    local generated = red:exists("subscriptions:tenant:" .. tenantId .. ":api:" .. artifactId .. ":key:" .. clientId)
    assert.are.same(1, generated)
    subscriptions.deleteSubscription(dataStore, artifactId, tenantId, clientId)
    generated = red:exists("subscriptions:tenant:" .. tenantId .. ":api:" .. artifactId .. ":key:" .. clientId)
    assert.are.same(0, generated)
  end)
end)

-- Generate fake hash
function generateHash(str)
  return string.byte(str)*13 + 2961
end
