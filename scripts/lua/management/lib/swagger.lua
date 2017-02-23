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

--- @module swagger
-- Module for parsing swagger file

local _M = {}

-- Convert passed-in swagger body to valid lua table
-- @param swagger swagger file to parse
function _M.parseSwagger(swagger)
  local backends = parseBackends(swagger)
  local policies = parsePolicies(swagger)
  local security = parseSecurity(swagger)
  local decoded = {
    name = swagger.info.title,
    basePath = swagger.basePath,
    resources = {}
  }
  for path, verbObj in pairs(swagger.paths) do
    decoded.resources[path] = { operations = {} }
    for verb, value in pairs(verbObj) do
      decoded.resources[path].operations[verb] = {}
      local verbObj = decoded.resources[path].operations[verb]
      local backend = (backends["all"] ~= nil) and backends["all"] or backends[value.operationId]
      verbObj.backendUrl = backend.backendUrl
      verbObj.backendMethod = (backend.backendMethod == 'keep') and verb or backend.backendMethod
      verbObj.policies = policies
      verbObj.security = security
    end
  end
  return decoded
end

--- Parse backendUrl and backendMethod
-- @param swagger swagger file to parse
function parseBackends(swagger)
  local configObj = swagger["x-gateway-configuration"]
  configObj = (configObj == nil) and swagger["x-ibm-configuration"] or configObj
  if configObj ~= nil then
    for _, obj in pairs(configObj.assembly.execute) do
      for policy, v in pairs(obj) do
        local res = {}
        if policy == "operation-switch" then
          local caseObj = v.case
          for _, case in pairs(caseObj) do
            for _, op in pairs(case.operations) do
              res[op] = {
                backendUrl = case.execute[1]["invoke"]["target-url"],
                backendMethod = case.execute[1]["invoke"].verb
              }
            end
          end
          return res
        end
        if policy == "invoke" then
          res["all"] = {
            backendUrl = v["target-url"],
            backendMethod = v.verb
          }
          return res
        end
      end
    end
  end
end

--- Parse policies in swagger
-- @param swagger swagger file to parse
function parsePolicies(swagger)
  local policies = {}
  -- parse rate limit
  policies = parseRateLimit(swagger, policies)
  policies = parseRequestMapping(swagger, policies)
  return policies
end

--- Parse rate limit
function parseRateLimit(swagger, policies)
  local rlObj = swagger["x-gateway-rate-limit"]
  rlObj = (rlObj == nil) and swagger["x-ibm-rate-limit"] or rlObj
  if rlObj ~= nil then
    rlObj = rlObj[1]
    if rlObj.unit == "second" then
      rlObj.unit = 1
    elseif rlObj.unit == "minute" then
      rlObj.unit = 60
    elseif rlObj.unit == "hour" then
      rlObj.unit = 3600
    elseif rlObj.unit == "day" then
      rlObj.unit = 86400
    else
      rlObj.unit = 60   -- default to minute
    end
    policies[#policies+1] = {
      type = "rateLimit",
      value = {
        interval = rlObj.unit * rlObj.units,
        rate = rlObj.rate,
        scope = "api",
        subscription = "true"
      }
    }
  end
  return policies
end

--- Parse request mapping
function parseRequestMapping(swagger, policies)
  local valueList = {}
  if swagger["x-ibm-configuration"] ~= nil then
    for _, obj in pairs(swagger["x-ibm-configuration"].assembly.execute) do
      for policy, v in pairs(obj) do
        if policy == "set-variable" then
          for _, actionObj in pairs(v.actions) do
            local fromValue = actionObj.value
            local toParsedArray = {string.match(actionObj.set, "([^.]+).([^.]+).([^.]+)") }
            local toName = toParsedArray[3]
            local toLocation = toParsedArray[2]
            toLocation = toLocation == "headers" and "header" or toLocation
            valueList[#valueList+1] = {
              action = "insert",
              from = {
                value = fromValue
              },
              to = {
                name = toName,
                location = toLocation
              }
            }
          end
        end
      end
    end
  end
  if next(valueList) ~= nil then
    policies[#policies+1] ={
      type = "reqMapping",
      value = valueList
    }
  end
  return policies
end

--- Parse security in swagger
-- @param swagger swagger file to parse
function parseSecurity(swagger)
  local security = {}
  if swagger["securityDefinitions"] ~= nil then
    local secObject = swagger["securityDefinitions"]
    for key, sec in pairs(secObject) do
      if sec.type == 'apiKey' then
        security[#security+1] = {
          type = sec.type,
          scope = "api",
          header = sec.name
        }
      elseif sec.type == 'oauth2' then
        security[#security+1] = {
          type = sec.type,
          scope = "api",
          provider = key
        }
      end
    end
  end
  return security
end

return _M
