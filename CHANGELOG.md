<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->
## 1.0.0
  - Fix array handling during mapping operations (#359)
  - Fix getUriPath logic to ignore API tenant base path (#363)
  - fix(http): Use HTTP 1.1 for upstreams (#369)
  - Disable ipv6 during DNS resolution (#366)
  -  Fix max body size limit (#365)
  - Fix App ID bug, add unit tests (#357)
  - Add support for preserving XF headers from upstream (#356)

## 0.11.0
  - OAuth fixes and improvements (#353)
  - Run test framework in a Docker container (#351)
  - Enable overriding the backend url to enable standalone mode (#347)

## 0.10.0-incubating
  - Guard against missing query parameters. (#343)
  - Add paging to getTenantAPIs (#335)
