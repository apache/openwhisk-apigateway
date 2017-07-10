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

--- @module logger
-- Module to handle logging in a single place
-- @author Cody Walker (cmwalker), Alex Song (songs)
local utils = require "lib/utils"

local _M = {}

--- Handle error stream
-- @param s String to write to error level of log stream
function _M.err(s)
  ngx.log(ngx.ERR, s)
end

--- Handle info logs
-- @param s String to write to info level of log stream
function _M.info(s)
  ngx.log(ngx.INFO, s)
end

--- Handle debug stream to stdout
-- @param s String to write to debug stream
function _M.debug(s)
  if s == nil then
    s = "nil"
  elseif type(s) == "table" then
    s = utils.serializeTable(s)
  elseif type(s) == "boolean" then
    s = (s == true) and "true" or "false"
  end
  os.execute("echo \"" .. s .. "\"")
end

return _M
