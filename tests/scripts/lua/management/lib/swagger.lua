--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

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
                      "subscription": true,
                      "interval": 180,
                      "rate": 100
                    }
                  }
                ],
                "security": [
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
                        "subscription": true,
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
                      "type": "clientSecret",
                      "scope": "api",
                      "idFieldName":"X-Api-Key",
                      "secretFieldName":"X-Api-Secret"
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
                        "subscription": true,
                        "interval": 180,
                        "rate": 100
                      }
                    },
                    {
                      "type": "reqMapping",
                      "value": [
                        {
                          "from": {
                            "value": "Basic xxx"
                          },
                          "to": {
                            "name": "Authorization",
                            "location": "header"
                          },
                          "action": "insert"
                        },
                        {
                          "from": {
                            "value": "bar"
                          },
                          "to": {
                            "name": "foo",
                            "location": "header"
                          },
                          "action": "insert"
                        }
                      ]
                    }
                  ],
                  "security": [
                    {
                      "type": "clientSecret",
                      "scope": "api",
                      "idFieldName":"X-Api-Key",
                      "secretFieldName":"X-Api-Secret"
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
    assert.are.same(expected, actual)
  end)

  it('should parse set-variable policy within operation-switch correctly', function()
    local expected = cjson.decode([[
        {
          "basePath": "/whisk2",
          "name": "Hello World API",
          "resources": {
            "/bye": {
              "operations": {
                "post": {
                  "backendUrl": "https://openwhisk.ng.bluemix.net/api/user@us.ibm.com/demo/createuser",
                  "policies": [],
                  "security": [],
                  "backendMethod": "post"
                },
                "get": {
                  "backendUrl": "https://openwhisk.ng.bluemix.net/api/some/action/path.http",
                  "policies": [
                    {
                      "type": "reqMapping",
                      "value": [
                        {
                          "from": {
                            "value": "bar"
                          },
                          "to": {
                            "name": "foo",
                            "location": "header"
                          },
                          "action": "insert"
                        },
                        {
                          "from": {
                            "value": "world"
                          },
                          "to": {
                            "name": "hello",
                            "location": "header"
                          },
                          "action": "insert"
                        }
                      ]
                    }
                  ],
                  "security": [],
                  "backendMethod": "get"
                }
              }
            }
          }
        }
      ]])
    local jsonPath = exampleBasePath .. 'example3.json'
    local jsonTable = loadJsonTable(jsonPath)
    local actual = swagger.parseSwagger(jsonTable)
    assert.are.same(expected, actual)
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
