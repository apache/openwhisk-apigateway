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

--- @module
--
-- @author Alex Song (songs)

local utils = require "lib/utils"
local cjson = require "cjson"

local _Request = {}

--- Error function to call when request is malformed
-- @param code error code
-- @param msg error message
function err(code, msg)
  ngx.header.content_type = "application/json; charset=utf-8"
  ngx.status = code
  local errObj = cjson.encode({
    status = code,
    message = utils.concatStrings({"Error: ", msg})
  })
  ngx.say(errObj)
  ngx.exit(ngx.status)
end

--- Function to call when request is successful
-- @param code status code
-- @param obj JSON encoded object to return
function success(code, obj)
  ngx.status = code
  if obj ~= nil then
    ngx.say(obj)
  end
  ngx.exit(ngx.status)
end

_Request.err = err
_Request.success = success

return _Request
