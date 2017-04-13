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
- **header** (optional): custom name of auth header (default is `x-api-key`)

Example:
```
"security":[
  {
    "type":"apiKey",
    "scope":"api",
    "header":"test"
  }
]
```

## Client Secret (`clientSecret`) 

Enforces Client ID / Client Secret pair authorization to secure api calls.
- **type**: `clientSecret`
- **scope**: `api`, `tenant`, `resource`
- **idFieldName** (optional): custom name of the client id header (default is `x-client-id`)
- **secretFieldName** (optional): custom name of the client secret header (default is `x-client-secret`) 

Example: 
```
"security":[
  {
    "type":"clientSecret",
    "scope":"api",
    "idFieldName":"X-IBM-ClientId",
    "secretFieldName":"X-IBM-ClientSecret"
  }
]
``` 

This will create two API keys for the API, which will need to be supplied in the `X-IBM-ClientId` and `X-IBM-ClientSecret` headers, respectively.

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
