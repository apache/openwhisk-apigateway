Management Interface v1
==============
The following defines the v1 interface for managing APIs and Tenants. These endpoints are exposed on port 9000.

## APIs

### PUT /v1/apis
Create a new API. Note that you should first create a tenant and obtain its `tenantId`. 

_body_:
```
{
  "name": *(string),
  "basePath": *(string),
  "tenantId": *(string),
  "resources": {
    "<path>": {
      "cors":{
        "origin": *(string),
        "methods": *(string)
      },
      "operations": {
        "<method>": {
          "backendMethod": *(string),
          "backendUrl": *(string),
          "policies": [
            {
              "type": *(string),
              "value": {}
            },
            ...
          ],
          "security": [
            {...}
          ]
        },
        ...
      }
    }
  }
}
```

See below for details on how to implement different policies and security:

- [policy definitions](https://github.com/openwhisk/openwhisk-apigateway/blob/master/doc/v1/policies.md)
- [security definitions](https://github.com/openwhisk/openwhisk-apigateway/blob/master/doc/v1/security.md)

_returns:_
```
{
  "id": (string),
  "name": (string),
  "basePath": (string),
  "tenantId": (string),
  "resources": {
   ...
  }
}
```

### PUT /v1/apis/{id}
Update attributes for a given API.

_body_:
```
{
  "name": *(string),
  "basePath": *(string),
  "tenantId": *(string),
  "resources": {
    "<path>": {
      "cors": { 
        "origin": *(string),
        "methods": *(string)
      },
      "operations": {
        "<method>": {
          "backendMethod": *(string),
          "backendUrl": *(string),
          "policies": [
            {
              "type": *(string),
              "value": {}
            },
            ...
          ],
          "security": [
            {...}
          ]
        },
        ...
      }
    }
  }
}
```

_returns:_
```
{
  "id": (string),
  "name": (string),
  "basePath": (string),
  "tenantId": (string),
  "resources": {
   ...
  }
}
```

### GET /v1/apis
Find all instances of APIs added to the gateway.

_returns:_
```
[
  {
    "id": (string),
    "name": (string),
    "basePath": (string),
    "tenantId": (string),
    "resources": {
     ...
    }
  }
]
```

### GET /v1/apis/{id}
Find an API by its id.

_returns:_
```
{
  "id": (string),
  "name": (string),
  "basePath": (string),
  "tenantId": (string),
  "resources": {
   ...
  }
}
```

### GET /v1/apis/{id}/tenant
Find the tenant associated with this API.

_returns:_
```
{
 "id": (string),
 "namespace" (string),
 "instance" (string)
}
```


### DELETE /v1/apis/{id}
Delete the API

_returns:_
```
{}
```

## Tenants

### PUT /v1/tenants
Create a new tenant.

_body:_
```
{
 "namespace": *(string),
 "instance": *(string)
}
```
_returns:_
```
{
 "id": (string),
 "namespace" (string),
 "instance" (string)
}
```

### PUT /v1/tenants/{id}
Update attributes for a given tenant.

_body:_
```
{
 "namespace": *(string),
 "instance": *(string)
}
```
_returns:_
```
{
 "id": (string),
 "namespace" (string),
 "instance" (string)
}
```

### GET /v1/tenants
Find all instances of tenants added to the gateway.

_returns:_
```
[
 {
  "id": (string),
  "namespace" (string),
  "instance" (string)
 }
]
```

### GET /v1/tenants/{id}
Find a tenant by its id.

_returns:_
```
{
 "id": (string),
 "namespace" (string),
 "instance" (string)
}
```

### DELETE /v1/tenants/{id}
Delete the tenant.

_returns:_
```
{}
```

### GET /v1/tenants/{id}/apis
Get all APIs for the given tenant.

_returns:_
```
[
  {
    "id": (string),
    "name": (string),
    "basePath": (string),
    "tenantId": (string),
    "resources": {
     ...
    }
  }
]
```


## Subscriptions
### PUT /v1/subscriptions
Add/update an api key for the specified tenant, resource, or api.

_body:_
```
{
  "key": *(string) The api key to store to redis.
  "scope": *(string) The scope to use the api key. "tenant", "resource", or "api".
  "tenantId": *(string) Tenant guid.
  "resource": (string) Resource path. Required if scope is "resource".
  "apiId": (string) API Guid. Required if scope is "API".
}
```

_Returns:_
```
Subscription created.
```

### DELETE /v1/subscriptions
Delete an api key associated with the specified tenant, resource or api.

_body:_
```
{
  "key": *(string) The api key to delete.
  "scope": *(string) The scope to use the api key. "tenant", "resource", or "api".
  "tenantId": *(string) Tenant guid.
  "resource": (string) Resource path. Required if scope is "resource".
  "apiId": (string) API Guid. Required if scope is "API".
}
```

_Returns:_
```
Subscription deleted.
```
