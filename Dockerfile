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

# apigateway
#
# VERSION               1.13.6.1
#
# From https://hub.docker.com/_/alpine/
#

FROM alpine:3.9

# Busybox's ash shell supports pipefail, which is useful for tarballs
SHELL [ "/bin/ash", "-o", "pipefail", "-c"]

# install dependencies
RUN apk update && \
    apk add \
    gcc tar libtool zlib perl tzdata \
    ca-certificates wget make musl-dev openssl-dev openssl pcre-dev g++ zlib-dev curl python \
    perl-test-longstring perl-list-moreutils perl-http-message geoip-dev dumb-init jq \
    && update-ca-certificates \
    && rm -rf /var/cache/apk/*

# openresty build
ENV OPENRESTY_VERSION=1.13.6.2 \
    PCRE_VERSION=8.37 \
    TEST_NGINX_VERSION=0.24 \
    OPM_VERSION=0.0.3 \
    LUA_RESTY_HTTP_VERSION=0.10 \
    LUA_RESTY_IPUTILS_VERSION=0.2.1 \
    LUA_RESTY_STRING_VERSION=0.09 \
    LUA_RESTY_LRUCACHE_VERSION=0.06 \
    LUA_RESTY_CJOSE_VERSION=0.4 \
    NETURL_LUA_VERSION=0.9-1 \
    CJOSE_VERSION=0.5.1 \
    LD_LIBRARY_PATH=/usr/local/lib \
    _prefix=/usr/local \
    _exec_prefix=/usr/local \
    _localstatedir=/var \
    _sysconfdir=/etc \
    _sbindir=/usr/local/sbin

RUN  if [ x`uname -m` = xs390x ]; then \
         echo "Building LuaJIT for s390x" \
	 && mkdir -p /tmp/luajit \
	 && cd /tmp/luajit \
	 && curl -k -L https://api.github.com/repos/linux-on-ibm-z/LuaJIT/tarball/v2.1 > luajit.tar.gz \
	 && tar -zxf luajit.tar.gz \
	 && cd linux-on-ibm-z-LuaJIT-* \
	 && make install \
	 && cd /tmp \
	 && rm -rf /tmp/luajit \
     ; fi

RUN  if [ x`uname -m` = xppc64le ]; then \
         echo "Building LuaJIT for ppc64le" \
         && mkdir /tmp/luajit  \
         && cd /tmp/luajit \
         && curl -k -L https://api.github.com/repos/PPC64/LuaJIT/tarball > luajit.tar.gz \
         && tar -zxf luajit.tar.gz \
         && cd PPC64-LuaJIT-* \
         && make && make install \
         && rm -rf /tmp/luajit \
     ; fi

RUN  echo " ... adding Openresty, NGINX and PCRE" \
     && mkdir -p /tmp/api-gateway \
     && readonly NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
     && echo "using up to $NPROC threads" \

     && cd /tmp/api-gateway/ \
     && curl -k -L https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz -o /tmp/api-gateway/pcre-${PCRE_VERSION}.tar.gz \
     && curl -k -L https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz -o /tmp/api-gateway/openresty-${OPENRESTY_VERSION}.tar.gz \
     && tar -zxf ./openresty-${OPENRESTY_VERSION}.tar.gz \
     && tar -zxf ./pcre-${PCRE_VERSION}.tar.gz \
     && cd /tmp/api-gateway/openresty-${OPENRESTY_VERSION} \
     && case "$(uname -m)" in \
        aarch64) \
          luajitdir="" \
          pcrejit="--with-pcre-jit" \
          ; echo " ... Patching ngx_lua and LuaJIT modules for ARM64 ... " \
          && rm -rf ./bundle/ngx_lua-* \
          && curl -k -L https://github.com/openresty/lua-nginx-module/archive/v0.10.14rc3.tar.gz \
            | tar -zxf - -C ./bundle \
          && mv ./bundle/lua-nginx-module-0.10.14rc3 ./bundle/ngx_lua-0.10.14rc3 \
          && rm -rf ./bundle/LuaJIT-* \
          && curl -k -L https://github.com/openresty/luajit2/archive/v2.1-20181029.tar.gz \
            | tar -zxf - -C ./bundle \
          && mv ./bundle/luajit2-2.1-20181029 ./bundle/LuaJIT-2.2.1-20181029 \
          ;; \
        s390x) \
          luajitdir="=/usr/local/" \
          pcrejit="" \
          ;; \
        ppc64le) \
          luajitdir="=/usr/local/" \
          pcrejit="--with-pcre-jit" \
          ;; \
        *) \
          luajitdir="" \
          pcrejit="--with-pcre-jit" \
          ;; \
      esac \
     && echo "        - building debugging version of the api-gateway ... " \
     && ./configure \
            --prefix=${_exec_prefix}/api-gateway \
            --sbin-path=${_sbindir}/api-gateway-debug \
            --conf-path=${_sysconfdir}/api-gateway/api-gateway.conf \
            --error-log-path=${_localstatedir}/log/api-gateway/error.log \
            --http-log-path=${_localstatedir}/log/api-gateway/access.log \
            --pid-path=${_localstatedir}/run/api-gateway.pid \
            --lock-path=${_localstatedir}/run/api-gateway.lock \
            --with-pcre=../pcre-${PCRE_VERSION}/ ${pcrejit} \
            --with-stream \
            --with-stream_ssl_module \
            --with-http_ssl_module \
            --with-http_stub_status_module \
            --with-http_realip_module \
            --with-http_addition_module \
            --with-http_sub_module \
            --with-http_dav_module \
            --with-http_geoip_module \
            --with-http_gunzip_module  \
            --with-http_gzip_static_module \
            --with-http_auth_request_module \
            --with-http_random_index_module \
            --with-http_secure_link_module \
            --with-http_degradation_module \
            --with-http_auth_request_module  \
            --with-http_v2_module \
            --with-luajit${luajitdir} \
            --without-http_ssi_module \
            --without-http_userid_module \
            --without-http_uwsgi_module \
            --without-http_scgi_module \
            --with-debug \
            -j${NPROC} \
    && make -j${NPROC} \
    && make install \

    && echo "        - building regular version of the api-gateway ... " \
    && ./configure \
            --prefix=${_exec_prefix}/api-gateway \
            --sbin-path=${_sbindir}/api-gateway \
            --conf-path=${_sysconfdir}/api-gateway/api-gateway.conf \
            --error-log-path=${_localstatedir}/log/api-gateway/error.log \
            --http-log-path=${_localstatedir}/log/api-gateway/access.log \
            --pid-path=${_localstatedir}/run/api-gateway.pid \
            --lock-path=${_localstatedir}/run/api-gateway.lock \
            --with-pcre=../pcre-${PCRE_VERSION}/ ${pcrejit} \
            --with-stream \
            --with-stream_ssl_module \
            --with-http_ssl_module \
            --with-http_stub_status_module \
            --with-http_realip_module \
            --with-http_addition_module \
            --with-http_sub_module \
            --with-http_dav_module \
            --with-http_geoip_module \
            --with-http_gunzip_module  \
            --with-http_gzip_static_module \
            --with-http_auth_request_module \
            --with-http_random_index_module \
            --with-http_secure_link_module \
            --with-http_degradation_module \
            --with-http_auth_request_module  \
            --with-http_v2_module \
            --with-luajit${luajitdir} \
            --without-http_ssi_module \
            --without-http_userid_module \
            --without-http_uwsgi_module \
            --without-http_scgi_module \
            -j${NPROC} \
    && make -j${NPROC} \
    && make install \

    && echo "        - adding Nginx Test support" \
    && curl -k -L https://github.com/openresty/test-nginx/archive/v${TEST_NGINX_VERSION}.tar.gz -o ${_prefix}/test-nginx-${TEST_NGINX_VERSION}.tar.gz \
    && cd ${_prefix} \
    && tar -xf ${_prefix}/test-nginx-${TEST_NGINX_VERSION}.tar.gz \
    && rm ${_prefix}/test-nginx-${TEST_NGINX_VERSION}.tar.gz \
    && cp -r ${_prefix}/test-nginx-0.24/inc/* /usr/local/share/perl5/site_perl/ \

    && ln -s ${_sbindir}/api-gateway-debug ${_sbindir}/nginx \
    && cp /tmp/api-gateway/openresty-${OPENRESTY_VERSION}/build/install ${_prefix}/api-gateway/bin/resty-install \
    && apk del g++ gcc make \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/api-gateway

RUN echo " ... installing opm..." \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/openresty/opm/archive/v${OPM_VERSION}.tar.gz -o /tmp/api-gateway/opm-${OPM_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/opm-${OPM_VERSION}.tar.gz -C /tmp/api-gateway \
    && cd /tmp/api-gateway/opm-${OPM_VERSION} \
    && cp bin/opm ${_prefix}/api-gateway/bin \
    && cd ${_prefix}/api-gateway \
    && mkdir -p site/manifest site/pod \
    && cd site \
    && ( [ -x ../lualib ] || ln -s ../lualib ./ ) \
    && ln -s ${_prefix}/api-gateway/bin/opm /usr/bin/opm \
    && ln -s ${_prefix}/api-gateway/bin/resty /usr/bin/resty \
    && rm -rf /tmp/api-gateway


RUN echo " ... installing opm packages ... " \
    && opm get pintsized/lua-resty-http=${LUA_RESTY_HTTP_VERSION} \
               hamishforbes/lua-resty-iputils=${LUA_RESTY_IPUTILS_VERSION} \
               openresty/lua-resty-string=${LUA_RESTY_STRING_VERSION} \
               openresty/lua-resty-lrucache=${LUA_RESTY_LRUCACHE_VERSION} \
               taylorking/lua-resty-cjose=${LUA_RESTY_CJOSE_VERSION} \
               taylorking/lua-resty-rate-limit

RUN echo " ... installing neturl.lua ... " \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/golgote/neturl/archive/${NETURL_LUA_VERSION}.tar.gz -o /tmp/api-gateway/neturl.lua-${NETURL_LUA_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/neturl.lua-${NETURL_LUA_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && export LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
    && cd /tmp/api-gateway/neturl-${NETURL_LUA_VERSION} \
    && cp lib/net/url.lua ${LUA_LIB_DIR} \
    && rm -rf /tmp/api-gateway

RUN echo " ... installing cjose ... " \
    && apk add automake autoconf git gcc make jansson jansson-dev \
    && mkdir -p /tmp/api-gateway \
    && curl -L -k https://github.com/cisco/cjose/archive/${CJOSE_VERSION}.tar.gz -o /tmp/api-gateway/cjose-${CJOSE_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/cjose-${CJOSE_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/cjose-${CJOSE_VERSION} \
    && sh configure \
    && make && make install \
    && rm -rf /tmp/api-gateway

ENV CONFIG_SUPERVISOR_VERSION 1.0.1-RC1
COPY build_config_supervisor.sh /tmp/build_config_supervisor.sh
RUN sh +x /tmp/build_config_supervisor.sh

COPY init.sh /etc/init-container.sh
# add the default configuration for the Gateway
COPY . /etc/api-gateway
RUN adduser -S nginx-api-gateway \
    && addgroup -S nginx-api-gateway

EXPOSE 80 8080 8423 9000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/etc/init-container.sh"]
