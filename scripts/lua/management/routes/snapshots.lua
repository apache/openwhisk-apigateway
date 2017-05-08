local request = require "lib/request" 

local _M = {} 

function _M.requestHandler()
  local snapshotId = ngx.var.snapshot_id 
  local redis = require('lib/redis')
  redis.setSnapshotId(snapshotId) 
  request.success(200)
end

return _M 
