Routes
==============
The following defines the interface for managing APIs and Tenants. These endpoints are exposed to port 9000.

## APIs

### PUT /apis
Create a new API. Note that you should first create a tenant and obtain its `tenantId`. For API policy definitions, see [here](policies.md).

_body_:
```
{
  "name": *(string),
  "basePath": *(string),
  "tenantId": *(string),
  "resources": {
    "path": {
      "operations": {
        "get": {
          "backendMethod": *(string),
          "backendUrl": *(string),
          "policies": [
            {
              "type": *(string),
              "value": {}
            }
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

### PUT /apis/{id}
Update attributes for a given API.

_body_:
```
{
  "name": *(string),
  "basePath": *(string),
  "tenantId": *(string),
  "resources": {
    "path": {
      "operations": {
        "get": {
          "backendMethod": *(string),
          "backendUrl": *(string),
          "policies": [
            {
              "type": *(string),
              "value": {}
            }
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

### GET /apis
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

### GET /apis/{id}
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

### GET /apis/{id}/tenant
Find the tenant associated with this API.

_returns:_
```
{
 "id": (string),
 "namespace" (string),
 "instance" (string)
}
```


### DELETE /apis/{id}
Delete the API

_returns:_
```
{}
```

## Tenants

### PUT /tenants
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

### PUT /tenants/{id}
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

### GET /tenants
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

### GET /tenants/{id}
Find a tenant by its id.

_returns:_
```
{
 "id": (string),
 "namespace" (string),
 "instance" (string)
}
```

### DELETE /tenants/{id}
Delete the tenant.

_returns:_
```
{}
```

### GET /tenants/{id}/apis
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
### PUT /subscriptions
Add/update an api key for the specified tenant, resource, or api.

_body:_
```
{
  "key": *(string) The api key to store to redis.
  "scope": *(string) The scope to use the api key. "tenant", "resource", or "api".
  "tenant": *(string) Tenant guid.
  "resource": (string) Resource path. Required if scope is "resource".
  "api": (string) API Guid. Required if scope is "API".
}
```

_Returns:_
```
Subscription created.
```

### DELETE /subscriptions
Delete an api key associated with the specified tenant, resource or api.

_body:_
```
{
  "key": *(string) The api key to delete.
  "scope": *(string) The scope to use the api key. "tenant", "resource", or "api".
  "tenant": *(string) Tenant guid.
  "resource": (string) Resource path. Required if scope is "resource".
  "api": (string) API Guid. Required if scope is "API".
}
```

_Returns:_
```
Subscription deleted.
```