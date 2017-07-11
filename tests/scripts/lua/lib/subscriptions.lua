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
