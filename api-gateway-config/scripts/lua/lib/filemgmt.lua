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

--- @module filemgmt
-- Creates the Nginx Conf files
-- @author Alex Song (songs), David Green (greend)

local utils = require "lib/utils"
local cjson = require "cjson"
local request = require "lib/request"

local _M = {}

--- Create/overwrite Nginx Conf file for given resource
-- @param baseConfDir the base directory for storing conf files for managed resources
-- @param tenant the namespace for the resource
-- @param gatewayPath the gateway path of the resource
-- @param resourceObj object containing different operations/policies for the resource
-- @return fileLocation location of created/updated conf file
function _M.createResourceConf(baseConfDir, tenant, gatewayPath, resourceObj)
  local decoded = cjson.decode(resourceObj)
  resourceObj = utils.serializeTable(decoded)
  local prefix = utils.concatStrings({
    "\tinclude /etc/api-gateway/conf.d/commons/common-headers.conf;\n",
    "\tset $upstream https://172.17.0.1;\n",
    "\tset $tenant ", tenant, ";\n",
    "\tset $backendUrl '';\n",
    "\tset $gatewayPath '", ngx.unescape_uri(gatewayPath), "';\n"
  })
  if decoded.apiId ~= nil then
    prefix = utils.concatStrings({prefix, "\tset $apiId ", decoded.apiId, ";\n"})
  end
  -- Add CORS headers
  prefix = utils.concatStrings({prefix, "\tadd_header Access-Control-Allow-Methods 'GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS';\n"})
  -- Set resource headers and mapping by calling routing.processCall()
  local outgoingResource = utils.concatStrings({
    "\taccess_by_lua_block {\n",
    "\t\tlocal routing = require \"routing\"\n",
    "\t\trouting.processCall(", resourceObj, ")\n",
    "\t}\n",
    "\tproxy_pass $upstream;\n"
  })
  -- Add to endpoint conf file
  os.execute(utils.concatStrings({"mkdir -p ", baseConfDir, tenant}))
  local fileLocation = utils.concatStrings({baseConfDir, tenant, "/", gatewayPath, ".conf"})
  local file, err = io.open(fileLocation, "w")
  if not file then
    request.err(500, utils.concatStrings({"Error adding to endpoint conf file: ", err}))
  end
  local updatedPath = ngx.unescape_uri(gatewayPath):gsub("%{(%w*)%}", utils.convertTemplatedPathParam)
  local location = utils.concatStrings({
    "location ~ ^/api/", tenant, "/", updatedPath, "(\\b) {\n",
    prefix,
    outgoingResource,
    "}\n"
  })
  file:write(location)
  file:close()
  -- reload nginx to refresh conf files
  os.execute("/usr/local/sbin/nginx -s reload")
  return fileLocation
end

--- Delete Ngx conf file for given resource
-- @param baseConfDir the base directory for storing conf files for managed resources
-- @param tenant the namespace for the resource
-- @param gatewayPath the gateway path of the resource
-- @return fileLocation location of deleted conf file
function _M.deleteResourceConf(baseConfDir, tenant, gatewayPath)
  local fileLocation = utils.concatStrings({baseConfDir, tenant, "/", gatewayPath, ".conf"})
  os.execute(utils.concatStrings({"rm -f ", fileLocation}))
  -- reload nginx to refresh conf files
  os.execute("/usr/local/sbin/nginx -s reload")
  return fileLocation
end

return _M
