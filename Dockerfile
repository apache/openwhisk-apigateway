# apigateway
#
# VERSION               1.9.7.3
#
# From https://hub.docker.com/_/alpine/
#
FROM alpine:latest

# install dependencies
RUN apk update \
    && apk add gcc tar libtool zlib jemalloc jemalloc-dev perl \ 
    make musl-dev openssl-dev pcre-dev g++ zlib-dev curl python \
    perl-test-longstring perl-list-moreutils perl-http-message \
    geoip-dev nodejs

ENV ZMQ_VERSION 4.0.5
ENV CZMQ_VERSION 2.2.0

# Installing throttling dependencies
RUN echo " ... adding throttling support with ZMQ and CZMQ" \
         && curl -L https://github.com/zeromq/zeromq4-x/archive/v${ZMQ_VERSION}.tar.gz -o /tmp/zeromq.tar.gz \
         && cd /tmp/ \
         && tar -xf /tmp/zeromq.tar.gz \
         && cd /tmp/zeromq*/ \
         && apk add automake autoconf \
         && ./autogen.sh \
         && ./configure --prefix=/usr \
                        --sysconfdir=/etc \
                        --mandir=/usr/share/man \
                        --infodir=/usr/share/info \
         && make && make install \
         && curl -L https://github.com/zeromq/czmq/archive/v${CZMQ_VERSION}.tar.gz -o /tmp/czmq.tar.gz \
         && cd /tmp/ \
         && tar -xf /tmp/czmq.tar.gz \
         && cd /tmp/czmq*/ \
         && ./autogen.sh \
         && ./configure --prefix=/usr \
                        --sysconfdir=/etc \
                        --mandir=/usr/share/man \
                        --infodir=/usr/share/info \
         && make && make install \
         && apk del automake autoconf \
         && rm -rf /tmp/zeromq* && rm -rf /tmp/czmq* \
         && rm -rf /var/cache/apk/*

# openresty build
ENV OPENRESTY_VERSION=1.9.7.3 \
    NAXSI_VERSION=0.53-2 \
    PCRE_VERSION=8.37 \
    TEST_NGINX_VERSION=0.24 \
    _prefix=/usr/local \
    _exec_prefix=/usr/local \
    _localstatedir=/var \
    _sysconfdir=/etc \
    _sbindir=/usr/local/sbin

RUN  echo " ... adding Openresty, NGINX, NAXSI and PCRE" \
     && mkdir -p /tmp/api-gateway \
     && readonly NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
     && echo "using up to $NPROC threads" \

     && cd /tmp/api-gateway/ \
     && curl -k -L https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz -o /tmp/api-gateway/naxsi-${NAXSI_VERSION}.tar.gz \
     && curl -k -L http://downloads.sourceforge.net/project/pcre/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.gz -o /tmp/api-gateway/pcre-${PCRE_VERSION}.tar.gz \
     && curl -k -L https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz -o /tmp/api-gateway/openresty-${OPENRESTY_VERSION}.tar.gz \
     && tar -zxf ./openresty-${OPENRESTY_VERSION}.tar.gz \
     && tar -zxf ./pcre-${PCRE_VERSION}.tar.gz \
     && tar -zxf ./naxsi-${NAXSI_VERSION}.tar.gz \
     && cd /tmp/api-gateway/openresty-${OPENRESTY_VERSION} \ 

     && echo "        - building debugging version of the api-gateway ... " \
     && ./configure \
            --prefix=${_exec_prefix}/api-gateway \
            --sbin-path=${_sbindir}/api-gateway-debug \
            --conf-path=${_sysconfdir}/api-gateway/api-gateway.conf \
            --error-log-path=${_localstatedir}/log/api-gateway/error.log \
            --http-log-path=${_localstatedir}/log/api-gateway/access.log \
            --pid-path=${_localstatedir}/run/api-gateway.pid \
            --lock-path=${_localstatedir}/run/api-gateway.lock \
            --add-module=../naxsi-${NAXSI_VERSION}/naxsi_src/ \
            --with-pcre=../pcre-${PCRE_VERSION}/ --with-pcre-jit \
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
            --with-luajit \
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
            --add-module=../naxsi-${NAXSI_VERSION}/naxsi_src/ \
            --with-pcre=../pcre-${PCRE_VERSION}/ --with-pcre-jit \
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
            --with-luajit \
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

ENV LUA_RESTY_HTTP_VERSION 0.07
RUN echo " ... installing lua-resty-http..." \
    && apk update \
    && apk add make \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/pintsized/lua-resty-http/archive/v${LUA_RESTY_HTTP_VERSION}.tar.gz -o /tmp/api-gateway/lua-resty-http-${LUA_RESTY_HTTP_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/lua-resty-http-${LUA_RESTY_HTTP_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/lua-resty-http-${LUA_RESTY_HTTP_VERSION} \
    && make install \
            LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
            INSTALL=${_prefix}/api-gateway/bin/resty-install \
    && rm -rf /tmp/api-gateway

ENV LUA_RESTY_IPUTILS_VERSION 0.2.0
RUN echo " ... installing lua-resty-iputils..." \
    && apk update \
    && apk add make \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/hamishforbes/lua-resty-iputils/archive/v${LUA_RESTY_IPUTILS_VERSION}.tar.gz -o /tmp/api-gateway/lua-resty-iputils-${LUA_RESTY_IPUTILS_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/lua-resty-iputils-${LUA_RESTY_IPUTILS_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/lua-resty-iputils-${LUA_RESTY_IPUTILS_VERSION} \
    && export LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
    && export INSTALL=${_prefix}/api-gateway/bin/resty-install \
    && $INSTALL -d ${LUA_LIB_DIR}/resty \
    && $INSTALL lib/resty/*.lua ${LUA_LIB_DIR}/resty/ \
    && rm -rf /tmp/api-gateway

ENV SHA1_LUA_VERSION 0.5.0
RUN echo " ... installing sha1.lua ... " \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/kikito/sha1.lua/archive/v${SHA1_LUA_VERSION}.tar.gz -o /tmp/api-gateway/sha1.lua-${SHA1_LUA_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/sha1.lua-${SHA1_LUA_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && export LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
    && cd /tmp/api-gateway/sha1.lua-${SHA1_LUA_VERSION} \
    && cp sha1.lua ${LUA_LIB_DIR} \
    && rm -rf /tmp/api-gateway

ENV NETURL_LUA_VERSION 0.9-1
RUN echo " ... installing neturl.lua ... " \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/golgote/neturl/archive/${NETURL_LUA_VERSION}.tar.gz -o /tmp/api-gateway/neturl.lua-${NETURL_LUA_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/neturl.lua-${NETURL_LUA_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && export LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
    && cd /tmp/api-gateway/neturl-${NETURL_LUA_VERSION} \
    && cp lib/net/url.lua ${LUA_LIB_DIR} \
    && rm -rf /tmp/api-gateway

ENV HMAC_LUA_VERSION 1.0.0
RUN echo " ... installing api-gateway-hmac ..." \
    && apk update \
    && apk add make \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/adobe-apiplatform/api-gateway-hmac/archive/${HMAC_LUA_VERSION}.tar.gz -o /tmp/api-gateway/api-gateway-hmac-${HMAC_LUA_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/api-gateway-hmac-${HMAC_LUA_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/api-gateway-hmac-${HMAC_LUA_VERSION} \
    && cp -r /usr/local/test-nginx-${TEST_NGINX_VERSION}/* ./test/resources/test-nginx/ \
    && make test \
    && make install \
            LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
            INSTALL=${_prefix}/api-gateway/bin/resty-install \
    && rm -rf /tmp/api-gateway

ENV CACHE_MANAGER_VERSION 1.0.1
RUN echo " ... installing api-gateway-cachemanager..." \
    && apk update \
    && apk add make \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/adobe-apiplatform/api-gateway-cachemanager/archive/${CACHE_MANAGER_VERSION}.tar.gz -o /tmp/api-gateway/api-gateway-cachemanager-${CACHE_MANAGER_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/api-gateway-cachemanager-${CACHE_MANAGER_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/api-gateway-cachemanager-${CACHE_MANAGER_VERSION} \
    && cp -r /usr/local/test-nginx-${TEST_NGINX_VERSION}/* ./test/resources/test-nginx/ \
    && apk update && apk add redis \
    && REDIS_SERVER=/usr/bin/redis-server make test \
    && make install \
            LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
            INSTALL=${_prefix}/api-gateway/bin/resty-install \
    && apk del redis \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/api-gateway

ENV REQUEST_VALIDATION_VERSION 1.1.1
RUN echo " ... installing api-gateway-request-validation ..." \
    && apk update \
    && apk add make \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/adobe-apiplatform/api-gateway-request-validation/archive/${REQUEST_VALIDATION_VERSION}.tar.gz -o /tmp/api-gateway/api-gateway-request-validation-${REQUEST_VALIDATION_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/api-gateway-request-validation-${REQUEST_VALIDATION_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/api-gateway-request-validation-${REQUEST_VALIDATION_VERSION} \
    && cp -r /usr/local/test-nginx-${TEST_NGINX_VERSION}/* ./test/resources/test-nginx/ \
    && apk update && apk add redis \
    && REDIS_SERVER=/usr/bin/redis-server make test \
    && make install \
            LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
            INSTALL=${_prefix}/api-gateway/bin/resty-install \
    && apk del redis \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/api-gateway

ENV ASYNC_LOGGER_VERSION 1.0.1
RUN echo " ... installing api-gateway-async-logger ..." \
    && apk update \
    && apk add make \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/adobe-apiplatform/api-gateway-async-logger/archive/${ASYNC_LOGGER_VERSION}.tar.gz -o /tmp/api-gateway/api-gateway-async-logger-${ASYNC_LOGGER_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/api-gateway-async-logger-${ASYNC_LOGGER_VERSION}.tar.gz -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/api-gateway-async-logger-${ASYNC_LOGGER_VERSION} \
    && cp -r /usr/local/test-nginx-${TEST_NGINX_VERSION}/* ./test/resources/test-nginx/ \
#    && make test \
    && make install \
            LUA_LIB_DIR=${_prefix}/api-gateway/lualib \
            INSTALL=${_prefix}/api-gateway/bin/resty-install \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/api-gateway

ENV ZMQ_ADAPTOR_VERSION 0.1.1
RUN echo " ... installing api-gateway-zmq-adaptor" \
         && curl -L https://github.com/adobe-apiplatform/api-gateway-zmq-adaptor/archive/${ZMQ_ADAPTOR_VERSION}.tar.gz -o /tmp/api-gateway-zmq-adaptor-${ZMQ_ADAPTOR_VERSION} \
         && apk update \
         && apk add check-dev g++ gcc \
         && cd /tmp/ \
         && tar -xf /tmp/api-gateway-zmq-adaptor-${ZMQ_ADAPTOR_VERSION} \
         && cd /tmp/api-gateway-zmq-adaptor-* \
         && make test \
         && PREFIX=/usr/local/sbin make install \
         && rm -rf /tmp/api-gateway-zmq-adaptor-* \
         && apk del check-dev g++ gcc \
         && rm -rf /var/cache/apk/*

ENV ZMQ_LOGGER_VERSION 1.0.0
RUN echo " ... installing api-gateway-zmq-logger ..." \
        && mkdir -p /tmp/api-gateway \
        && curl -L https://github.com/adobe-apiplatform/api-gateway-zmq-logger/archive/${ZMQ_LOGGER_VERSION}.tar.gz -o /tmp/api-gateway/api-gateway-zmq-logger-${ZMQ_LOGGER_VERSION}.tar.gz \
        && tar -xf /tmp/api-gateway/api-gateway-zmq-logger-${ZMQ_LOGGER_VERSION}.tar.gz -C /tmp/api-gateway/ \
        && cd /tmp/api-gateway/api-gateway-zmq-logger-${ZMQ_LOGGER_VERSION} \
        && cp -r /usr/local/test-nginx-${TEST_NGINX_VERSION}/* ./test/resources/test-nginx/ \
        && make test \
        && make install \
             LUA_LIB_DIR=/usr/local/api-gateway/lualib \
             INSTALL=/usr/local/api-gateway/bin/resty-install \
        && rm -rf /tmp/api-gateway

ENV REQUEST_TRACKING_VERSION 1.0.1
RUN echo " ... installing api-gateway-request-tracking ..." \
        && mkdir -p /tmp/api-gateway \
        && curl -L https://github.com/adobe-apiplatform/api-gateway-request-tracking/archive/${REQUEST_TRACKING_VERSION}.tar.gz -o /tmp/api-gateway/api-gateway-request-tracking-${REQUEST_TRACKING_VERSION}.tar.gz \
        && tar -xf /tmp/api-gateway/api-gateway-request-tracking-${REQUEST_TRACKING_VERSION}.tar.gz -C /tmp/api-gateway/ \
        && cd /tmp/api-gateway/api-gateway-request-tracking-${REQUEST_TRACKING_VERSION} \
        && cp -r /usr/local/test-nginx-${TEST_NGINX_VERSION}/* ./test/resources/test-nginx/ \
        && apk update && apk add redis \
        && REDIS_SERVER=/usr/bin/redis-server make test \
        && make install \
             LUA_LIB_DIR=/usr/local/api-gateway/lualib \
             INSTALL=/usr/local/api-gateway/bin/resty-install \
        && apk del redis \
        && rm -rf /tmp/api-gateway

RUN \
    curl -L -k -s -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 \
    && apk update \
    && apk add gawk \
    && chmod 755 /usr/local/bin/jq \
    && rm -rf /var/cache/apk/*

COPY init.sh /etc/init-container.sh
ONBUILD COPY init.sh /etc/init-container.sh

# add the default configuration for the Gateway
COPY api-gateway-config /etc/api-gateway
RUN adduser -S nginx-api-gateway \
    && addgroup -S nginx-api-gateway
ONBUILD COPY api-gateway-config /etc/api-gateway

COPY management /var/gateway-mgmt
ONBUILD COPY management /var/gateway-mgmt
RUN mkdir /etc/api-gateway/managed_confs \
    && echo " ... installing node dependencies" \
    && cd /var/gateway-mgmt
#    && npm install

EXPOSE 80 8080 8423 9000


ENTRYPOINT ["/etc/init-container.sh"]
