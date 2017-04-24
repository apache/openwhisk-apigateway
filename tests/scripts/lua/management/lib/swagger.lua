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

local cjson = require 'cjson'
local lfs = require 'lfs'
local swagger = require 'management/lib/swagger'
local exampleBasePath = lfs.currentdir() .. '/scripts/lua/management/examples/'

describe('Testing v2 management interface', function()
  it('should parse native swagger correctly', function()
    local expected = cjson.decode([[
      {
        "basePath": "/native",
        "name": "Hello World API",
        "resources": {
          "/hello": {
            "cors": {
              "origin": "true"
            },
            "operations": {
              "get": {
                "backendUrl": "https://appconnect.mybluemix.net",
                "policies": [
                  {
                    "type": "rateLimit",
                    "value": {
                      "scope": "api",
                      "subscription": "true",
                      "interval": 180,
                      "rate": 100
                    }
                  }
                ],
                "security": [
                  {
                    "type": "oauth2",
                    "provider": "google",
                    "scope": "api"
                  },
                  {
                    "type": "apiKey",
                    "header": "X-Api-Key",
                    "scope": "api"
                  }
                ],
                "backendMethod": "get"
              }
            }
          }
        }
      }
    ]])
    local jsonPath = exampleBasePath .. 'example1.json'
    local jsonTable = loadJsonTable(jsonPath)
    local actual = swagger.parseSwagger(jsonTable)
    assert.are.same(expected, actual)
  end)

  it('should parse whisk swagger correctly', function()
    local expected = cjson.decode([[
        {
          "basePath": "/whisk",
          "name": "Hello World API",
          "resources": {
            "/hello": {
              "operations": {
                "post": {
                  "backendUrl": "https://openwhisk.ng.bluemix.net/api/user@us.ibm.com/demo/createuser",
                  "policies": [
                    {
                      "type": "rateLimit",
                      "value": {
                        "scope": "api",
                        "subscription": "true",
                        "interval": 180,
                        "rate": 100
                      }
                    },
                    {
                      "type": "reqMapping",
                      "value": [{
                        "from": {
                          "value": "Basic xxx"
                        },
                        "to": {
                          "name": "Authorization",
                          "location": "header"
                        },
                        "action": "insert"
                      }]
                    }
                  ],
                  "security": [
                    {
                      "type": "oauth2",
                      "provider": "google",
                      "scope": "api"
                    },
                    {
                      "type": "apiKey",
                      "header": "X-Api-Key",
                      "scope": "api"
                    }
                  ],
                  "backendMethod": "post"
                },
                "get": {
                  "backendUrl": "https://openwhisk.ng.bluemix.net/api/some/action/path.http",
                  "policies": [
                    {
                      "type": "rateLimit",
                      "value": {
                        "scope": "api",
                        "subscription": "true",
                        "interval": 180,
                        "rate": 100
                      }
                    },
                    {
                      "type": "reqMapping",
                      "value": [{
                        "from": {
                          "value": "Basic xxx"
                        },
                        "to": {
                          "name": "Authorization",
                          "location": "header"
                        },
                        "action": "insert"
                      }]
                    }
                  ],
                  "security": [
                    {
                      "type": "oauth2",
                      "provider": "google",
                      "scope": "api"
                    },
                    {
                      "type": "apiKey",
                      "header": "X-Api-Key",
                      "scope": "api"
                    }
                  ],
                  "backendMethod": "get"
                }
              }
            }
          }
        }
      ]])
    local jsonPath = exampleBasePath .. 'example2.json'
    local jsonTable = loadJsonTable(jsonPath)
    local actual = swagger.parseSwagger(jsonTable)
    assert.are.same(expected.resources["/hello"].operations.post.policies[2].value, actual.resources["/hello"].operations.post.policies[2].value)
  end)
end)

function loadJsonTable(path)
  local contents
  local file = io.open(path, "r" )
  if file then
    contents = file:read("*a")
    local decoded = cjson.decode(contents)
    io.close( file )
    return decoded
  end
  return nil
end
