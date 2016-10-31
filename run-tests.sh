#!/bin/bash

# Run unit tests
cd api-gateway-config/tests
busted -c --output=TAP test.lua

# Generate code coverage report
luacov ../scripts/lua/
cat luacov.report.out
rm luacov.report.out && rm luacov.stats.out