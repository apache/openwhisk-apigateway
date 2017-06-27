#define NULL 0
#include <cjose/jwk.h>
#include <cjose/jws.h>
#include <stdio.h>
#include <string.h>

// This code uses the cjose library to perform jwt introspection since lua-resty-jwt is not capable of performing JWS verification at this time.


bool verify_jwt(char* key, char* token) {
  
  cjose_err* err = NULL;
  cjose_jwk_t* jwk = cjose_jwk_import(key, strlen(key), err);
  if (err != NULL) {
    return false;
  }
  err = NULL;
  cjose_jws_t* jws = cjose_jws_import(token, strlen(token), err);  
  bool result = cjose_jws_verify(jws, jwk, err);
  if (err != NULL) {
    cjose_jwk_release(jwk);
    return false;
  }
  cjose_jwk_release(jwk);
  cjose_jws_release(jws);
  return result;

}
