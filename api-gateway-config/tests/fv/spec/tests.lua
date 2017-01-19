local adminPort = 9000
local managedURL = os.getenv("PUBLIC_MANAGEDURL")
local managedPort = os.getenv("PUBLIC_MANAGEDURL_PORT") 
local requests = require("requests")
local cjson = require("cjson")

local tenantId = ''
local apiId = ''

describe('Testing api gateway functionality', function()

  it('Creates a tenant', function() 
    local tenant = {
      namespace = "test",
      instance = "test"
    }
    local url = "http://127.0.0.1:" .. adminPort .. "/v1/tenants" 
    local headers = {}
    headers['Content-Type'] = 'application/json'
    response = requests.post({url = url, headers = headers, data=cjson.encode(tenant) })
    assert.is_not.falsy(response.id)
  end)
  it('Creates an API', function()
    local obj = { 
      
      
    }

  end)
  it('Deletes an API', function() 


  end) 
  it('Creates an API with API Key security', function() 
    
  end)
  
  it('Creates an API with OAuth security', function() 

  end)




  it('Forwards API Calls to backend URL', function()
  end)
  
  it('Forwards API Calls to backend URL with OAuth security', function() 

  end)
  it('Rate limits APIs correctly', function() 


  end)
end)
