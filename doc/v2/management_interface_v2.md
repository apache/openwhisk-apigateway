Management Interface v2
==============

The following defines the v2 interface for managing APIs using the [OpenAPI 2.0 spec](http://swagger.io/specification/). 

## API

See below for details on how to create, update, and delete managed APIs inside the apigateway, as well as how to manage subscription keys for securing the managed APIs. Note that these endpoints are exposed on port 9000.

<details>
<summary><b>Manage APIs</b></summary>

---
### POST /v2/{tenant_id}/apis
Create a new managed API.

* `tenant_id`: *(string) the tenant associated with this API
* The body is a JSON object that follows the [OpenAPI 2.0 spec](http://swagger.io/specification/), with additional [gateway-specific extensions](#gateway-specific-extensions)

_Example body_:

```
{
  "swagger": "2.0",
  "info": {
    "version": "1.0",
    "title": "Hello World API"
  },
  "basePath": "/hw",
  "schemes": [
    "https"
  ],
  "consumes": [
    "application/json"
  ],
  "produces": [
    "application/json"
  ],
  "paths": {
    "/hello": {
      "get": {
        "description": "Returns a greeting to the user!",
        "operationId": "getHello",
        "responses": {
          "200": {
            "description": "Returns the greeting.",
            "schema": {
              "type": "string"
            }
          }
        }
      }
    },
    "/foo": {
      "get": {
        "description": "Returns bar to the user.",
        "operationId": "getFoo",
        "responses": {
          "200": {
            "description": "Returns bar.",
            "schema": {
              "type": "string"
            }
          }
        }
      }
    }
  },
  "securityDefinitions": {
    "client_id": {
      "type": "apiKey",
      "name": "X-Api-Key",
      "in": "header"
    }
  },
  "security": [
    {
      "client_id": []
    }
  ],
  "x-gateway-rate-limit": [
    {
      "unit": "minute",
      "units": 3,
      "rate": 100
    }
  ],
  "x-gateway-configuration": {
    "assembly": {
      "execute": [
        {
          "set-variable": {
            "actions": [
              {
                "set": "message.headers.Authorization",
                "value": "Basic xxx"
              }
            ]
          }
        },
        {
          "operation-switch": {
            "case": [
              {
                "operations": [
                  "getHello"
                ],
                "execute": [
                  {
                    "invoke": {
                      "target-url": "https://openwhisk.ng.bluemix.net/api/some/action/path.http",
                      "verb": "keep"
                    }
                  }
                ]
              },
              {
                "operations": [
                  "postHello"
                ],
                "execute": [
                  {
                    "invoke": {
                      "target-url": "https://openwhisk.ng.bluemix.net/api/another/action/path.http",
                      "verb": "keep"
                    }
                  }
                ]
              }
            ],
            "otherwise": []
          }
        }
      ]
    }
  }
}

```

_returns:_

```
{
  "artifact_id": (string),
  "managed_url": (string),
  "open_api_doc": (object)
}
```
 * `artifact_id`: the id associated with this API
 * `managed_url`: the base url to use to invoke this API
 * `open_api_doc`: the OpenAPI doc

Once you have created your API, you can invoke this API by concatenating the `managed_url` with a path specified in your OpenAPI doc.


### PUT /v2/{tenant_id}/apis
Update an existing managed API.

* `tenant_id`: *(string) the tenant associated with this API
* The body is a JSON object that represents this API's [OpenAPI 2.0 spec](http://swagger.io/specification/), as decribed above

_returns:_

```
{
  "artifact_id": (string),
  "managed_url": (string),
  "open_api_doc": (object)
}
```
 * `artifact_id`: the id associated with this API
 * `managed_url`: the base url to use to invoke this API
 * `open_api_doc`: the OpenAPI doc

### GET /v2/{tenant_id}/apis
Get all managed APIs for a tenant.

* `tenant_id`: *(string) the tenant associated with this API

_returns:_

```
[
  {
    "artifact_id": (string),
    "managed_url": (string),
    "open_api_doc": (object)
  },
  {
    "artifact_id": (string),
    "managed_url": (string),
    "open_api_doc": (object)
  },
  ...
]
```
 * `artifact_id`: the id associated with this API
 * `managed_url`: the base url to use to invoke this API
 * `open_api_doc`: the OpenAPI doc
 
### GET /v2/{tenant_id}/apis/{artifact_id}
Get a specific managed API for a tenant by its id.

* `tenant_id`: *(string) the tenant associated with this API
* `artifact_id`: *(string) the id associated with this API

_returns:_

```
{
  "artifact_id": (string),
  "managed_url": (string),
  "open_api_doc": (object)
}
```
 * `artifact_id`: the id associated with this API
 * `managed_url`: the base url to use to invoke this API
 * `open_api_doc`: the OpenAPI doc
 
### DELETE /v2/{tenant_id}/apis/{artifact_id}
Delete a specific managed API for a tenant by its id.

* `tenant_id`: *(string) the tenant associated with this API
* `artifact_id`: *(string) the id associated with this API

_returns:_

```
204 No Content
```

</details>


<details>
<summary><b>Manage Subscriptions</b></summary>

---
### POST /v2/{tenant_id}/subscriptions
Create a client_id and/or client_secret for a managed API.

* `tenant_id`: *(string) the tenant associated with this API

_body_:

```
{
  artifact_id: *(string),
  client_id: *(string),
  client_secret: (string)
}
```
* `artifact_id`: the id associated with this API
* `client_id`: the client id associated with this subscription for this API
* `client_secret`: optional client secret associated with this subscription for this API. Note that once a client_secret has been created, there is no way to retrieve its value as it is stored as a hash inside the gateway.
  
_returns:_

```
{
  "message": "Subscription 'clientId' created for API 'artifactId'"
}
```

### GET /v2/{tenant_id}/subscriptions?artifact_id={artifact_id}
Get all subscriptions associated with a managed API.

* `tenant_id`: *(string) the tenant associated with this API
* `artifact_id`: *(string) the id associated with this API

_returns:_

```
[
  client_id_1,
  client_id_2,
  ...
]
```

### DELETE /v2/{tenant_id}/subscriptions/{client_id}?artifact_id={artifact_id}
Delete a specific subscription for an API.

* `tenant_id`: *(string) the tenant associated with this API
* `client_id`: *(string) the client id associated with this subscription for this API
* `artifact_id`: *(string) the id associated with this API

_returns:_

```
204 No Content
```

</details>


## Gateway-specific Extensions
See below for a list of policies that are supported in the gateway and how they can be configured inside the OpenAPI doc.
* <b>Target-url and Operation-switch</b>

  Set the target-url (ie. the backend for your API) for all paths using the `invoke` policy inside the `x-gateway-configuration` extension.
  
  _Example:_
  ```
  "x-gateway-configuration": {
    "assembly": {
      "execute": [
        {
          "invoke": {
            "target-url": "https://openwhisk.ng.bluemix.net/api/some/action/path.http",
            "verb": "keep"
          }
        },
        ...
      ]
    }
  }
  ```
  * `target-url`: the backend url
  * `verb`: the method to use when invoking the target-url (use "keep" to use the keep the same verb as the API)
  
  To set a different `target-url` for different paths, use the `operation-switch` policy inside `x-gateway-configuration`.
  
  _Example:_
  ```
  "x-gateway-configuration": {
    "assembly": {
      "execute": [
        {
          "operation-switch": {
            "case": [
              {
                "operations": [
                  "getHello"
                ],
                "execute": [
                  {
                    "invoke": {
                      "target-url": "https://openwhisk.ng.bluemix.net/api/some/action/path.http",
                      "verb": "keep"
                    }
                  }
                ]
              },
              {
                "operations": [
                  "postHello"
                ],
                "execute": [
                  {
                    "invoke": {
                      "target-url": "https://openwhisk.ng.bluemix.net/api/another/action/path.http",
                      "verb": "keep"
                    }
                  }
                ]
              }
            ],
            "otherwise": []
          }
        }
      ]
    }
  }
  ```
  * inside the `operations` array for each case, specify the `operationId` of the path to which you want the `target-url` to apply

* <b>Client Id and Client Secret</b>
  
  Secure your managed API with a client id and an optional client secret.
  
  _Example:_
  ```
  "securityDefinitions": {
    "client_id": {
      "type": "apiKey",
      "name": "X-Api-Key",
      "in": "header"
    },
    "client_secret": {
      "type": "apiKey",
      "name": "X-Api-Secret",
      "in": "header"
    }
  }
  ```
  * Currently, only `apiKey` is supported for the "type" field and only `header` is supported for the "in" field
  * Client ids and client secrets can be created using the Subscriptions API described in the [API](#api) section

* <b>Rate Limiting</b>

  Rate limit your managed API using the [Leaky Bucket](https://en.wikipedia.org/wiki/Leaky_bucket) algorithm.
  
  _Example:_
  ```
  "x-gateway-rate-limit": [
    {
      "unit": "minute",
      "units": 3,
      "rate": 100
    }
  ]
  ```
  * `unit`: a string representing the unit of time (eg. "second", "minute", "hour", "day")
  * `units`: the number of units
  * `rate`: the number of allowed calls for the specified time

* <b>CORS</b>

  Enable or disable CORS (Cross-Origin Resource Sharing) using the `x-gateway-configuration` extension.
  
  _Example:_
  
  ```
  "x-gateway-configuration": {
    "cors": {
      "enabled": true
    },
    ...
  }
  ```
  * valid values for the "enabled" field are `true` and `false`
