local _Utils = {}

--- Concatenate a list of strings into a single string. This is more efficient than concatenating
-- strings together with "..", which creates a new string every time
-- @param list List of strings to concatenate
-- @return concatenated string
function _Utils.concatStrings(list)
    local t = {}
    for k,v in ipairs(list) do
        t[#t+1] = tostring(v)
    end
    return table.concat(t)
end

function serializeTable(t)
  local tt = '{'
  local first = true
  for k, v in pairs(t) do
    if first == false then
      tt = tt .. ', '
    else
      first = false
    end
    if type(k) == 'string' then
      tt = tt .. tostring(k) .. ' = '
    end
    if type(v) == 'table' then
      print('found table')
      tt = tt .. serializeTable(v)
    elseif type(v) == 'string' then
      print('did not find table: ' .. tostring(k) .. '; ' .. tostring(v))
      tt = tt .. '"' .. tostring(v) .. '"'
    else
      print('did not find table: ' .. tostring(k) .. '; ' .. tostring(v))
      tt = tt .. tostring(v)
    end
  end
  tt = tt .. '}'
  return tt
end

_Utils.serializeTable = serializeTable

return _Utils