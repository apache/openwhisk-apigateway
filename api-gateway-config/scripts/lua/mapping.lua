--- @module mapping
local mapping = {}

local logger = require("logger")
local json = require("json")

local body = nil
local query = nil
local headers = nil

function mapping.processMap(map)
  getRequestParams()
  for k, v in pairs(map) do
    if v.action == "insert" then
      insertParam(v)
    elseif v.action == "remove" then
      removeParam(v)
    elseif v.action == "transform" then
      transformParam(v)
    else
      logger.err('Map action not recognized. Skipping... ' .. v.action)
    end
  end
  finalize()
end

function getRequestParams()
  body =  ngx.req.get_body_data()
  if body == nil then
    body = {}
  end
  query = ngx.req.get_uri_args()
  headers = ngx.resp.get_headers()
end

function insertParam(m)
  logger.debug('in add param; to: ' .. m.to.name .. '|' .. m.to.location);
  local v = nil
  local k = m.to.name
  if m.from.value ~= nil then
    v = m.from.value
  elseif m.from.location == 'header' then
    v = headers[m.from.name]
  elseif m.from.location == 'query' then
    v = query[m.from.name]
  elseif m.from.location == 'body' then
    v = body[m.from.name]
  end
  -- determine to where
  if m.to.location == 'header' then
    insertHeader(k, v)
  elseif m.to.location == 'query' then
    insertQuery(k, v)
  elseif m.to.location == 'body' then
    insertBody(k, v)
  end
end

function removeParam(m)
  logger.debug('in remove param; to: ' .. m.from.name .. '|' .. m.from.location);
  if m.from.location == "header" then
    removeHeader(m.from.name)
  elseif m.from.location == "query" then
    removeQuery(m.from.name)
  elseif m.from.location == "body" then
    removeBody(m.from.name)
  end
end

function transformParam(m)
  logger.debug('in transform param; from: ' .. m.from.name .. '|' .. m.from.location .. '; to: ' .. m.to.name .. '|' .. m.to.location)
  if m.from.name == '*' then
    transformAllParams(m.from.location, m.to.location)
  else
    insertParam(m)
    removeParam(m)
  end
end

function transformAllParams(s, d)
  if s == 'query' then
    logger.debug('transforming all query params')
    for k, v in pairs(query) do
      logger.debug('transform param: ' .. k)
      local t = {}
      t.from = {}
      t.from.name = k
      t.from.location = s
      t.to = {}
      t.to.name = k
      t.to.location = d
      insertParam(t)
      removeParam(t)
    end
  elseif s == 'header' then
    logger.debug('transforming all header params')
    for k, v in pairs(headers) do
      logger.debug('transform param: ' .. k)
      local t = {}
      t.from = {}
      t.from.name = k
      t.from.location = s
      t.to = {}
      t.to.name = k
      t.to.location = d
      insertParam(t)
      removeParam(t)
    end
  elseif s == 'body' then
    logger.debug('transforming all body params')
    for k, v in pairs(body) do
      logger.debug('transform param: ' .. k)
      local t = {}
      t.from = {}
      t.from.name = k
      t.from.location = s
      t.to = {}
      t.to.name = k
      t.to.location = d
      insertParam(t)
      removeParam(t)
    end
  end
end

function finalize()
  local bodyJson = json.convertLuaTable(body)
  ngx.req.set_body_data(bodyJson)
  ngx.req.set_uri_args(query)
end

function insertHeader(k, v)
  ngx.req.set_header(k, v)
end

function insertQuery(k, v)
  query[k] = v
end

function insertBody(k, v)
  body[k] = v
end

function removeHeader(k)
  ngx.req.clear_header(k)
end

function removeQuery(k)
  query[k] = nil
end

function removeBody(k)
  body[k] = nil
end

return mapping