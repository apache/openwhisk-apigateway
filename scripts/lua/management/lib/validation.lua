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

--- @module validation
-- Module for validating api body

local cjson = require "cjson"
local utils = require "lib/utils"

local _M = {}

--- Error checking for policies and security
-- @param policies policies object
-- @param security security object
local function checkOptionalPolicies(policies, security)
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

--- Error checking for operations
-- @param operations operations object
local function checkOperations(operations)
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
    for _, v in pairs(requiredFields) do
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

--- Error checking for resources
-- @param resources resources object
local function checkResources(resources)
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

--- Check JSON body fields for errors
-- @param ds edis client instance
-- @param field name of field
-- @param object field object
local function isValid(dataStore, field, object)
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
    local tenant = dataStore:getTenant(object)
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

function _M.validate(dataStore, decoded)
  local fields = {"name", "basePath", "tenantId", "resources"}
  for _, v in pairs(fields) do
    local res, err = isValid(dataStore, v, decoded[v])
    if res == false then
      return err
    end
  end
  return nil
end

return _M
