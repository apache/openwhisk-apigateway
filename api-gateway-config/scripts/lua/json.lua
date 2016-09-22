--- @module json
local json = {}

local cjson = require "cjson"

function json.convertJSONObj(obj)
    local decoded = nil
    local jsonBody = ""
    for key, value in pairs(obj) do
        jsonBody = jsonBody .. value
        -- Handle case where the "=" character is inside any of the strings in the json body
        --if(value ~= true) then
        --    jsonBody = jsonBody .. "=" .. value
        --end
    end
    return cjson.decode(jsonBody)
end

function json.convertLuaTable(t)
  return cjson.encode(t)
end

return json