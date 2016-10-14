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
docker run -p 80:80 -p 9000:9000 \
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
#### PUT /subscriptions/{namespace}/{url-encoded-resource}/{api-key}
Add/update an api key for a given resource. Alternatively, call `PUT /subscriptions/{namespace}/{api-key}` to create an api key for the namespace.

_Returns:_
```
Subscription created.
```

#### DELETE /subscriptions/{namespace}/{url-encoded-resource}/{api-key}
Delete an api key associated with the resource. Alternatively, call DELETE /subscriptions/{namespace}/{api-key} to delete an api key associated with the namespace.

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

