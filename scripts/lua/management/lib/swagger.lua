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

--- @module swagger
-- Module for parsing swagger file

local _M = {}

-- Convert passed-in swagger body to valid lua table
-- @param swagger swagger file to parse
function _M.parseSwagger(swagger)
  local backends = parseBackends(swagger)
  local policies = parsePolicies(swagger)
  local security = parseSecurity(swagger)
  local corsObj = parseCors(swagger)
  local decoded = {
    name = swagger.info.title,
    basePath = swagger.basePath,
    resources = {}
  }
  for path, verbObj in pairs(swagger.paths) do
    decoded.resources[path] = { operations = {} }
    decoded.resources[path].cors = corsObj
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
  local unit
  if rlObj ~= nil then
    rlObj = rlObj[1]
    if rlObj.unit == "second" then
      unit = 1
    elseif rlObj.unit == "minute" then
      unit = 60
    elseif rlObj.unit == "hour" then
      unit = 3600
    elseif rlObj.unit == "day" then
      unit = 86400
    else
      unit = 60   -- default to minute
    end
    policies[#policies+1] = {
      type = "rateLimit",
      value = {
        interval = unit * rlObj.units,
        rate = rlObj.rate,
        scope = "api",
        subscription = true
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

function parseCors(swagger)
  local cors = { origin = nil, methods = nil }
  local configObj = swagger["x-gateway-configuration"]
  configObj = (configObj == nil) and swagger["x-ibm-configuration"] or configObj
  if configObj.cors ~= nil then
    if configObj.cors.enabled == true then
      cors.origin = "true"
    elseif configObj.cors.enabled == false then
      cors.origin = "false"
    end
    return cors
  end
  return nil
end

return _M
