-- An initialization script on a per worker basis.
-- User: ddascal
-- Date: 07/12/14
-- Time: 16:44
--

local _M = {}


--- Loads a lua gracefully. If the module doesn't exist the exception is caught, logged and the execution continues
-- @param module path to the module to be loaded
--
local function loadrequire(module)
    ngx.log(ngx.DEBUG, "Loading module [" .. tostring(module) .. "]")
    local function requiref(module)
        require(module)
    end

    local res = pcall(requiref, module)
    if not (res) then
        ngx.log(ngx.WARN, "Could not load module [", module, "].")
        return nil
    end
    return require(module)
end



ngx.apiGateway = _M

