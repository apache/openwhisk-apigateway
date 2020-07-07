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
local utils = require "lib/utils"

-- Convert passed-in swagger body to valid lua table
-- @param swagger swagger file to parse
function _M.parseSwagger(swagger)
  local backends = parseBackends(swagger)
  local policies = parseSwaggerPolicies(swagger)
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
      verbObj.policies = utils.deepCloneTable(policies) or {}
      verbObj.security = security
      if backends ~= nil then
        local backend = (backends["all"] ~= nil) and backends["all"] or backends[value.operationId]
        verbObj.backendUrl = backend.backendUrl
        verbObj.backendMethod = (backend.backendMethod == 'keep') and verb or backend.backendMethod
        if backend.policy ~= nil then
          local globalReqMappingPolicy = nil;
          for _, policy in pairs(verbObj.policies) do
            if policy.type == 'reqMapping' then
              globalReqMappingPolicy = policy;
            end
          end
          if globalReqMappingPolicy ~= nil then
            for _, v in pairs(backend.policy.value) do
              globalReqMappingPolicy.value[#globalReqMappingPolicy.value+1] = v
            end
          else
            verbObj.policies[#verbObj.policies+1] = {
              type = 'reqMapping',
              value = backend.policy.value
            }
          end
        end
      else
        verbObj.backendUrl = ''
        verbObj.backendMethod = verb
      end
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
              res[op] = {}
              for _, opPolicy in pairs(case.execute) do
                if opPolicy.invoke ~= nil then
                  res[op].backendUrl = opPolicy.invoke["target-url"]
                  res[op].backendMethod = opPolicy.invoke.verb
                elseif opPolicy["set-variable"] ~= nil then
                  local reqMappingPolicy = parseRequestMapping(case)
                  if reqMappingPolicy ~= nil then
                    res[op].policy = reqMappingPolicy
                  end
                end
              end
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
function parseSwaggerPolicies(swagger)
  local policies = {}
  -- parse rate limit
  local rlObj = swagger["x-gateway-rate-limit"]
  rlObj = (rlObj == nil) and swagger["x-ibm-rate-limit"] or rlObj
  local rateLimitPolicy = parseRateLimit(rlObj)
  if rateLimitPolicy ~= nil then
    policies[#policies+1] = rateLimitPolicy
  end
  -- parse set-variable
  local configObj = swagger["x-gateway-configuration"]
  configObj = (configObj == nil) and swagger["x-ibm-configuration"] or configObj
  if configObj ~= nil then
    local reqMappingPolicy = parseRequestMapping(configObj.assembly)
    if reqMappingPolicy ~= nil then
      policies[#policies+1] = reqMappingPolicy
    end
  end
  return policies
end

--- Parse rate limit
function parseRateLimit(rlObj)
  if rlObj ~= nil and rlObj[1] ~= nil then
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
    return {
      type = "rateLimit",
      value = {
        interval = unit * rlObj.units,
        rate = rlObj.rate,
        scope = "api",
        subscription = true
      }
    }
  end
  return nil
end

--- Parse request mapping
function parseRequestMapping(configObj)
  local valueList = {}
  if configObj ~= nil then
    for _, obj in pairs(configObj.execute) do
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
    return {
      type = "reqMapping",
      value = valueList
    }
  else
    return nil
  end
end

--- Parse security in swagger
-- @param swagger swagger file to parse
function parseSecurity(swagger)
  local security = {}
  if swagger["securityDefinitions"] ~= nil then
    local secObject = swagger["securityDefinitions"]
    if utils.tableLength(secObject) == 2 then
      secObj = {
        type = 'clientSecret',
        scope = 'api'
      }
      for key, sec in pairs(secObject) do
        if key == 'client_id' then
          secObj.idFieldName = sec.name
        elseif key == 'client_secret' then
          secObj.secretFieldName = sec.name
        end
      end
      security[#security+1] = secObj
    else
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
