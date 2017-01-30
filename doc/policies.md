Policies
==============
The following defines the different policies that can be used when creating an API. The currently supported policies are:
`reqMapping`, `rateLimit`.


###rateLimit:
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

###reqMapping:
Supported actions: `remove`, `default`, `insert`, `transform`.  
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
This will remove the `password` field from the body of the incoming request, so it's not passed to the backendURL  

_default:_  
Only `body`, `header`, `query` parameters can have default values.  
```
{
   "action":"default",
   "from":{
      "value":"BASIC XXX"
   },
   "to":{
      "name":"Authorization",
      "location":"header"
   }
}
```
This will assign the value of `BASIC XXX` to a `header` called `Authorization` but only if the value is not already set.  

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

_Path Parameter Mappings:_  
To map a path parameter from the incoming Url to a path parameter on the backend Url, you will need to wrap brackets `{}` around the path parameter on the incoming Url as well as the backend Url, for example:  
`IP:Port/resources/tenant_id/serverless/{myAction}/restified`
```
"backendURL":"https://openwhisk.stage1.ng.bluemix.net/api/v1/namespaces/APIC-Whisk_test/actions/{ACTION}?blocking=true&result=true",
"policies":
  [{
    "type": "reqMapping",
    "value": [{
        "action": "transform",
        "from": {
          "name": "myAction",
          "location": "path"
        },
        "to": {
          "name": "ACTION",
          "location": "path"
        }
      }]
  }]
```
If a path is then invoked on `/serverless/Hello World/restified`, then the value from `{myAction}`, which is `Hello World`, will be assigned to the variable `ACTION` on the backend path.


##Security
Supported types: `apiKey, oauth`.  
_scope:_ `api`, `tenant`, `resource`.  
_header:_ _(optional)_ custom name of auth header (default is x-api-key)  

```
"security":[{
        "type":"apiKey",
        "scope":"api",
        "header":"<MyCustomAuthHeader>"
    }
]
```
This will add security of an `apiKey`, at the API level, and uses the header call `myCustomAuthHeader`.  
NOTE: Security added at the Tenant level will affect all APIs and resources under that Tenant. Likewise, security added at the API level will affect all resources under that API.
