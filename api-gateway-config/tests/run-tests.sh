#!/bin/bash

# Run unit tests
busted -c --output=TAP --helper=set_paths spec/test.lua

# Generate code coverage report
luacov ../scripts/lua/
cat luacov.report.out
rm luacov.report.out && rm luacov.stats.out