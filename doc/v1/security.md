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

Security
==============
The following defines the different security policies you can enforce on your APIs.

## Currently supported security policies:
- `apiKey`
- `clientSecret`
- `oauth2`

## API Key (`apiKey`)

Enforces API Key authorization to secure api calls.

- **type**: `apiKey`
- **scope**: `api`, `tenant`, `resource`
- **name** (optional): custom name of auth header (default is `x-api-key`)
- **location** (optional): location where the apiKey is passed, either as a header ('header') or query string ('query') (default is `header`)

Example:
```
"security":[
  {
    "type":"apiKey",
    "scope":"api",
    "name":"test",
    "location":"header"
  }
]
```

## Client Secret (`clientSecret`)

Enforces Client ID / Client Secret pair authorization to secure api calls.
- **type**: `clientSecret`
- **scope**: `api`, `tenant`, `resource`
- **idFieldName** (optional): custom name of the client id header (default is `x-client-id`)
- **secretFieldName** (optional): custom name of the client secret header (default is `x-client-secret`)
- **location** (optional): location where the clientId and clientSecret are passed, either as a header ('header') or query string ('query') (default is `header`)

Example:
```
"security":[
  {
    "type":"clientSecret",
    "scope":"api",
    "idFieldName":"X-IBM-ClientId",
    "secretFieldName":"X-IBM-ClientSecret",
    "location": "header"
  }
]
```

This will create two API keys for the API, which will need to be supplied in the `X-IBM-ClientId` and `X-IBM-ClientSecret` headers or query strings, respectively.

## OAuth 2.0 (`oauth2`)

Perform token introspection for various social login providers and enforce token validation on that basis.

- **type**: `oauth2`
- **scope**: `api`, `tenant`, `resource`
- **provider**: which oauth token provider to use (facebook, google, github)

Example:
```
"security":[
  {
    "type":"apiKey",
    "scope":"api",
    "header":"test"
  },
  {
    "type":"oauth2",
    "scope":"api",
    "provider":"google"
  }
]
```

This will require that an apikey is supplied in the `test` header, and a valid google OAuth token must be specified in the `authorization` header.
