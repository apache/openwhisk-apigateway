apigateway
=============
A performant API Gateway based on Openresty and NGINX.

Table of Contents
=================

* [Quick Start](#quick-start)
* [API](#api)
  * [Resources](#resources)
  * [Subscriptions](#subscriptions)
* [Developer Guide](#developer-guide)


Quick Start
===========

```
docker run -p 80:80 -p 8080:8080 -p 9000:9000 \
            -e REDIS_HOST=<redis_host> \
            -e REDIS_PORT=<redis_port> \
            -e REDIS_PASS=<redis_pass> \
            apicgw/apigateway:latest
```

This command starts an API Gateway that subscribes to the Redis instance with the specified host and port. The `REDIS_PASS` variable is optional and is required only when redis needs authentication. 

On startup, the API Gateway looks for pre-existing resources in redis, whose keys are defined as `resources:<namespace>:<resource>`, and creates nginx conf files associated with those resources. Then, it listens for any resource key changes in redis and updates nginx conf files appropriately. These conf files are stored in the running docker container at `/etc/api-gateway/managed_confs/<namespace>/<resource>.conf`.


API
==============
The following endpoints are exposed to port 9000.

## Resources
#### PUT /resources/{namespace}/{url-encoded-resource}
Create/update and expose a new resource on the gateway associated with a namespace and a url-encoded resource, with the implementation matching the passed values.

_body:_
```
{
  "gatewayMethod": *(string) The method that you would like your newly exposed API to listen on.
  "backendURL": *(string) The fully qualified URL that you would like your invoke operation to target.
  "backendMethod": (string) The method that you would like the invoke operation to use. If none is supplied, the gatewayMethod will be used.
  "policies": *(array) A list of policy objects that will be applied during the execution of your resource.
  "security": (object) An optional json object defining security policies (e.g. {"type": "apikey"} )
}
```

_Returns:_
```
{
  "managedUrl": (string) The URL at which you can invoke your newly created resource.
}
```

####Policies
The currently supported policies are: `reqMapping`, `rateLimit`.

#####rateLimit:
_interval:_ the time interval that the rate is applied to.  
_rate:_ the number of calls allowed per interval of time.  
_scope:_ `api`, `tenant`, `resource`.  
_subscription:_ `true`, `false`.  
If subscription is `true`, the rateLimit applies to each user with a vaild subscription.  
If subscription is `false`, the rateLimit applies the collective usage from all users.  
```
  "interval":60,
  "rate":10,
  "scope":"api"
  "subscription": "false"
```
This will set a rateLimit ratio of 10 calls per 60 second, at an API level.  
This rateLimit is shared across all users (subescription:false).

#####reqMapping:
Supported actions: `remove`, `insert`, `transform`.  
Supported locations: `body`, `path`, `header`, `query`.  

_remove:_
```
{
   "action":"remove",
   "from":{
      "value":"<password>"
      "location":"body"
   }
}
```
This will remove the `password` field from the body of the incoming request, so it is not sent to the backendURL

_insert:_
```
{
   "action":"insert",
   "from":{
      "value":"application/json"
   },
   "to":{
      "name":"Content-type",
      "location":"header"
   }
}
```
This will insert the value of `application/json` into a `header` named `Content-type` on the backend request

_transform:_
```
{
   "action":"transform",
   "from":{
      "name":"*",
      "location":"query"
   },
   "to":{
      "name":"*",
      "location":"body"
   }
}
```
This will transform all incoming `query` parameters into `body` parameters in the outgoing request to the backendURL.  
Where `*` is a wild card, or you can use the variable name.
```
policies":[
     {
        "type":"rateLimit",
        "value":[
            "interval":60,
            "rate":100,
            "scope":"api"
            "subscription": "true"
        ]
     },
        "type":"reqMapping",
        "value":[
        {
           "action":"transform",
           "from":{
              "name":"<user>",
              "location":"query"
           },
           "to":{
              "name":"<id>",
              "location":"body"
           }
        }]
     }]
```
Each user (subscription:true) will have a rateLimit ratio of 100 calls per 60 seconds at the API level.  
This will also assign the vaule from the `query` parameter named `user` to a body parameter named `id`.  

####Security
Supported types: `apiKey`.  
_scope:_ `api`, `tenant`, `resource`.  
_header:_ _(optional)_ custom name of auth header (default is x-api-key)  

```
"security": {
        "type":"apiKey",
        "scope":"api",
        "header":"<MyCustomAuthHeader>"
    }
```
This will add security of an `apiKey`, at the API level, and uses the header call `myCustomAuthHeader`.  
NOTE: Security added at the Tenant level will affect all APIs and resources under that Tenant. Likewise, security added at the API level will affect all resources under that API.

#### GET /resources/{namespace}/{url-encoded-resource}
Get the specified resource and return the managed url.

_Returns:_
```
{
  "managedUrl": (string) The URL at which you can invoke the resource.
}
```

#### DELETE /resources/{namespace}/{url-encoded-resource}
Delete the specified resource from redis and delete the corresponding conf file.

_Returns:_
```
Resource deleted.
```

#### GET /subscribe
This is called automatically on gateway startup. It subscribes to resource key changes in redis and creates/updates the necessary nginx conf files.


## Subscriptions
#### PUT /subscriptions
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

#### DELETE /subscriptions
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


Developer Guide
================

 To build the docker image locally use:
 ```
  make docker
 ```

 To Run the Docker image
 ```
  make docker-run-mgmt REDIS_HOST=<redis_host> REDIS_PORT=<redis_port> REDIS_PASS=<redis_pass>
 ```
 
 The main API Gateway process is exposed to port `80`. To test that the Gateway works see its `health-check`:
 ```
  $ curl http://<docker_host_ip>/health-check
    API-Platform is running!
 ```
 
##Testing

 Unit tests can be found in the `api-gateway-config/tests/spec` directory.

 First install the necessary dependencies:
 ```
  make test-build
 ```
 Then, run the unit tests:
 ```
  make test-run
 ```
 This will output the results of the tests as well as generate a code coverage report.

