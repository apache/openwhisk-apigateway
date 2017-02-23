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

--- @module validation
-- Module for validating api body

local cjson = require "cjson"
local redis = require "lib/redis"
local utils = require "lib/utils"

local _M = {}

function _M.validate(red, decoded)
  local fields = {"name", "basePath", "tenantId", "resources"}
  for _, v in pairs(fields) do
    local res, err = isValid(red, v, decoded[v])
    if res == false then
      return err
    end
  end
  return nil
end

--- Check JSON body fields for errors
-- @param red Redis client instance
-- @param field name of field
-- @param object field object
function isValid(red, field, object)
  -- Check that field exists in body
  if not object then
    return false, { statusCode = 400, message = utils.concatStrings({"Missing field '", field, "' in request body."}) }
  end
  -- Additional check for basePath
  if field == "basePath" then
    local basePath = object
    if string.match(basePath, "'") then
      return false, { statusCode = 400, message = "basePath contains illegal character \"'\"." }
    end
  end
  -- Additional check for tenantId
  if field == "tenantId" then
    local tenant = redis.getTenant(red, object)
    if tenant == nil then
      return false, { statusCode = 404, message = utils.concatStrings({"Unknown tenant id ", object }) }
    end
  end
  if field == "resources" then
    local res, err = checkResources(object)
    if res ~= nil and res == false then
      return res, err
    end
  end
  -- All error checks passed
  return true
end

--- Error checking for resources
-- @param resources resources object
function checkResources(resources)
  if next(resources) == nil then
    return false, { statusCode = 400, message = "Empty resources object." }
  end
  for path, resource in pairs(resources) do
    -- Check resource path for illegal characters
    if string.match(path, "'") then
      return false, { statusCode = 400, message = "resource path contains illegal character \"'\"." }
    end
    -- Check that resource path begins with slash
    if path:sub(1,1) ~= '/' then
      return false, { statusCode = 400, message = "Resource path must begin with '/'." }
    end
    -- Check operations object
    local res, err = checkOperations(resource.operations)
    if res ~= nil and res == false then
      return res, err
    end
  end
end

--- Error checking for operations
-- @param operations operations object
function checkOperations(operations)
  if not operations or next(operations) == nil then
    return false, { statusCode = 400, message = "Missing or empty field 'operations' or in resource path object." }
  end
  local allowedVerbs = {GET=true, POST=true, PUT=true, DELETE=true, PATCH=true, HEAD=true, OPTIONS=true}
  for verb, verbObj in pairs(operations) do
    if allowedVerbs[verb:upper()] == nil then
      return false, { statusCode = 400, message = utils.concatStrings({"Resource verb '", verb, "' not supported."}) }
    end
    -- Check required fields
    local requiredFields = {"backendMethod", "backendUrl"}
    for k, v in pairs(requiredFields) do
      if verbObj[v] == nil then
        return false, { statusCode = 400, message = utils.concatStrings({"Missing field '", v, "' for '", verb, "' operation."}) }
      end
      if v == "backendMethod" then
        local backendMethod = verbObj[v]
        if allowedVerbs[backendMethod:upper()] == nil then
          return false, { statusCode = 400, message = utils.concatStrings({"backendMethod '", backendMethod, "' not supported."}) }
        end
      end
    end
    -- Check optional fields
    local res, err = checkOptionalPolicies(verbObj.policies, verbObj.security)
    if res ~= nil and res == false then
      return res, err
    end
  end
end

--- Error checking for policies and security
-- @param policies policies object
-- @param security security object
function checkOptionalPolicies(policies, security)
  if policies then
    for _, v in pairs(policies) do
      local validTypes = {"reqMapping", "rateLimit", "backendRouting"}
      if (v.type == nil or v.value == nil) then
        return false, { statusCode = 400, message = "Missing field in policy object. Need \"type\" and \"value\"." }
      elseif utils.tableContains(validTypes, v.type) == false then
        return false, { statusCode = 400, message = "Invalid type in policy object. Valid: " .. cjson.encode(validTypes) }
      end
    end
  end
  if security then
    for _, sec in ipairs(security) do
      local validScopes = {"tenant", "api", "resource"}
      if (sec.type == nil or sec.scope == nil) then
        return false, { statusCode = 400, message = "Missing field in security object. Need \"type\" and \"scope\"." }
      elseif utils.tableContains(validScopes, sec.scope) == false then
        return false, { statusCode = 400, message = "Invalid scope in security object. Valid: " .. cjson.encode(validScopes) }
      end
    end
  end
end

return _M