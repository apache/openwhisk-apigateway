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

return _Utils
