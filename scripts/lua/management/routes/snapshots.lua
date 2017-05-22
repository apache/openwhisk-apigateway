local request = require "lib/request" 

local _M = {} 

function _M.requestHandler()
  local redis = require('lib/redis')
  local requestMethod = ngx.req.get_method() 
  if requestMethod == 'GET' then 
    request.success(200, redis.getSnapshotId())
  end 
  local snapshotId = ngx.var.snapshot_id 
  print('id: ' .. ngx.var.snapshot_id)
  local redis = require('lib/redis')
  redis.setSnapshotId(snapshotId) 
  request.success(200)
end

return _M 
