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

--- @module security
-- A module to load all and execute the security policies
-- @author David Green (greend), Alex Song (songs)

local _M = {}

local request = require "lib/request"
local utils = require "lib/utils"
--- Allow or block a request by calling a loaded security policy
-- @param securityObj an object out of the security array in a given tenant / api / resource
function process(securityObj)
  local ok, result = pcall(require, utils.concatStrings({'policies/security/', securityObj.type}))
  if not ok then
    ngx.log(ngx.ERR, 'An unexpected error ocurred while processing the security policy: ' .. securityObj.type)
    request.err(500, 'Gateway error.')
  end
  return result.process(securityObj)
end

-- Wrap process in code to load the correct module
_M.process = process

return _M
