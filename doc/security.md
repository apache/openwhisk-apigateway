Security
==============
The following defines the different security policies you can enforce on your APIs.

## Currently supported security policies:
- `apiKey`
- `oauth2`

## API Key (`apiKey`)

Enforce API calls to include an API Key.

- **type**: `apiKey`
- **scope**: `api`, `tenant`, `resource`
- **header** (optional): custom name of auth header (default is `x-api-key`)
- **hashed** (optional): `true`, `false`

Example:
```
"security":[
  {
    "type":"apiKey",
    "scope":"api",
    "header":"test"
  },
  {
    "type":"apiKey", 
    "scope":"resource"
    "header":"secret",
    "hashed":true
  }  
]
```

This will create two API keys for the API, which will need to be supplied in the `test` and `secret` headers, respectively.

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
