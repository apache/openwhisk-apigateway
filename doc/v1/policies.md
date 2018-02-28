<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for additional
# information regarding copyright ownership.  The ASF licenses this file to you
# under the Apache License, Version 2.0 (the # "License"); you may not use this
# file except in compliance with the License.  You may obtain a copy of the License
# at:
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
-->

Policies
==============
The following defines the different policies that can be used when creating an API. 

## Currently supported policies
- `rateLimit`
- `reqMapping`

## Rate Limiting (`rateLimit`)
This policy allows for rate limiting calls based on the [leaky bucket](https://en.wikipedia.org/wiki/Leaky_bucket) algorithm.
- **interval**: the time interval that the rate is applied to, in seconds.
- **rate**: the number of calls allowed per interval of time.  
- **scope**: `api`, `tenant`, `resource`.  
- **subscription** (optional): `true`, `false`.  
    - If subscription is `true`, the rate limit applies to each user with a vaild subscription.  
    - If subscription is `false`, the rate limit applies the collective usage from all users.  
    
Example:
```
{
  "type": "rateLimit",
  "value": {
    "interval": 60,
    "rate": 120,
    "scope": "api"
    "subscription": true
  }
}
```
The example above will rate limit an API for each subscription at 120 requests per 60 seconds, or 2 req/sec.

## Request Mapping (`reqMapping`)
This policy allows you to map incoming request values to various locations in the actual backend request. It generally adheres to the following template:
```
{
  "type": "reqMapping",
  "value": [
    {
      "action": "<action>",
      "from": {
        "name": "name1",
        "location": "<gatewayLocation>"
      },
      "to": {
        "name": "name2",
        "location": "<backendLocation>"
      },
    },
    ...
  ]
}
```
- Supported actions: `insert`, `transform`, `remove`, `default`
- Supported locations: `body`, `header`, `query`, `path`

If you want to perform multiple request mappings, you can add multiple objects into the `value` array. Note that depending on the type of action you want to perform, the structure of these objects will change slightly, as described in detail below.


### insert

Insert a new value in to the backend request.

Example:
```
{
   "action": "insert",
   "from": {
      "value": "application/json"
   },
   "to": {
      "name": "Content-type",
      "location": "header"
   }
}
```
This will insert the value of `application/json` into a `header` named `Content-type` on the backend request. Note that the format of the `from` block is different from the template above.

### transform

Move a value from the apigateway request to the backend request.

Example:
```
{
   "action":"transform",
   "from":{
      "name":"foo",
      "location":"query"
   },
   "to":{
      "name":"bar",
      "location":"body"
   }
}
```
This will move the value of the `foo` query parameter from the incoming request to the `bar` field in the backend request body. 

You can also specify `*` as the `name` for the mapping to apply for all fields in that location.

Example:
```
{
   "action": "transform",
   "from": {
      "name": "*",
      "location": "query"
   },
   "to": {
      "name": "*",
      "location": "body"
   }
}
```
This will move all incoming `query` parameters into the `body` in the backend request.  

#### Note on Path Parameter Mappings
To define a path parameter, you will need to wrap curly brackets `{}` around the path parameter in the url.

Example: 

Mapping an incoming path parameter to a backend path parameter

- Incoming URL: `/api/<tenantId>/test/{foo}/hello`
- Backend URL: `https://openwhisk.ng.bluemix.net/api/v1/namespaces/APIC-Whisk_test/actions/{MYACTION}`
- policy:
```
"policies":
  [{
    "type": "reqMapping",
    "value": [{
        "action": "transform",
        "from": {
          "name": "foo",
          "location": "path"
        },
        "to": {
          "name": "MYACTION",
          "location": "path"
        }
      }]
  }]
```

### remove

Remove a field from the request.

Example:
```
{
   "action": "remove",
   "from": {
      "name": "foo"
      "location": "body"
   }
}
```
This will remove the `foo` field from the body of the incoming request, so that it's not passed to the backend request.

### default

Insert a default value, if it's not supplied in the incoming request.

Example:
```
{
   "action": "default",
   "from": {
      "value": "bar"
   },
   "to": {
      "name": "foo",
      "location": "header"
   }
}
```
This will assign `bar` to a `header` called `foo`, but only if the value is not already set. Note that this policy is only supported for `body`, `header`, `query` locations.
