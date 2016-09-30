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

--- @module
--
-- @author Alex Song (songs), Cody Walker (cmwalker)

local logger = require "lib/logger"

local _Utils = {}

--- Concatenate a list of strings into a single string. This is more efficient than concatenating
-- strings together with "..", which creates a new string every time
-- @param list List of strings to concatenate
-- @return concatenated string
function concatStrings(list)
  local t = {}
  for k,v in ipairs(list) do
    t[#t+1] = tostring(v)
  end
  return table.concat(t)
end

--- Serializes a lua table, returning a string representation of the table.
-- Recursively calls itself it
-- Useful for saving a lua table to a file, as if not serialized it will save as "Table x35252"
-- @param t The lua table
function serializeTable(t)
  local first = true
  local tt = { '{' }
  for k, v in pairs(t) do
    if first == false then
      tt[#tt+1] = ', '
    else
      first = false
    end
    if type(k) == 'string' then
      tt[#tt+1] = concatStrings({tostring(k), ' = '})
    end
    if type(v) == 'table' then
      tt[#tt+1] = serializeTable(v)
    elseif type(v) == 'string' then
      tt[#tt+1] = concatStrings({'"', tostring(v), '"'})
    else
      tt[#tt+1] = tostring(v)
    end
  end
  tt[#tt+1] = '}'
  return table.concat(tt)
end

_Utils.concatStrings = concatStrings
_Utils.serializeTable = serializeTable

return _Utils
