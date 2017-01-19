#!/bin/sh
COUNTER=0 

if [[ -z $PUBLIC_MANAGEDURL_PORT ]]; then
  PUBLIC_MANAGED_URL_PORT=9000 
fi
while [[ $COUNTER -lt 100 ]]; do 
  RESULT=$(curl "http://127.0.0.1:$PUBLIC_MANAGEDURL_PORT/v1/health-check")
  if [[ -z $(echo $RESULT | grep ready) ]]; then 
    break
  fi
  sleep .5
done

busted --output=TAP --helper=set_paths spec/tests.lua
