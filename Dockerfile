# apigateway
#
# VERSION               1.9.7.3
#
# From https://hub.docker.com/_/alpine/
#

FROM alpine:latest

LABEL image_name=apigateway tags=1.9.7.3,1.9.7,1.9,latest

# install dependencies
#
#  Note that we use --no-cache to avoid having to update or (later) rm a cache
#  Using '--virtual' establishes a stack pointer (essentially) that lets us
#  remove everything we installed just to make the build work.
#
#  Also, added bash, dumb-init and jq packages.  The latter two had been
#  retrieved and compiled, so their addition should speed the Docker build.
#
RUN apk --no-cache add bash dumb-init geoip libgcc openssl-dev jq \
 && apk --no-cache add --virtual build-deps \
	   gcc tar automake autoconf libtool zlib jemalloc jemalloc-dev perl \
        jansson jansson-dev \
        ca-certificates wget make musl-dev pcre-dev g++ zlib-dev curl python \
        perl-test-longstring perl-list-moreutils perl-http-message geoip-dev \
 && update-ca-certificates

# openresty build
ENV OPENRESTY_VERSION=1.9.7.3 \
    NAXSI_VERSION=0.53-2 \
    PCRE_VERSION=8.37 \
    TEST_NGINX_VERSION=0.24 \
    LUAJIT_VERSION=2.1 \
    LUAJIT_DIR=/usr/local/api-gateway/luajit \
    _prefix=/usr/local \
    _exec_prefix=/usr/local \
    _localstatedir=/var \
    _sysconfdir=/etc \
    _sbindir=/usr/local/sbin

#
#  The S390X architecture needs a very specific patch to LuaJIT to work, so we download and
#  compile it here for OpenRESTY to use later.  The 'if' statement should prevent excess
#  work from happening on other builds.
#
RUN : \
 && if [ "`uname -m`" = "s390x" ]; then \
        echo " ... compiling and installing LuaJIT" \
     && mkdir -p /tmp/api-gateway/LuaJIT-${LUAJIT_VERSION} \
     && cd /tmp/api-gateway/LuaJIT-${LUAJIT_VERSION} \
     && echo 'Getting' https://api.github.com/repos/linux-on-ibm-z/LuaJIT/tarball/v${LUAJIT_VERSION} \
     && curl -sSL https://api.github.com/repos/linux-on-ibm-z/LuaJIT/tarball/v${LUAJIT_VERSION} | \
        tar zxf - --strip-components=1 \
     && make install PREFIX=${LUAJIT_DIR} \
     && rm -rf /tmp/api-gateway/LuaJIT-${LUAJIT_VERSION} \
 ; fi

RUN  echo " ... adding Openresty, NGINX, NAXSI and PCRE" \
     && mkdir -p /tmp/api-gateway \
     && readonly NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
     && echo "using up to $NPROC threads" \

     && cd /tmp/api-gateway/ \
     && curl -sSL https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz | tar zfx - \
     && curl -sSL http://downloads.sourceforge.net/project/pcre/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.gz | tar zfx - \
     && curl -sSL https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz | tar zfx - \

     && cd /tmp/api-gateway/openresty-${OPENRESTY_VERSION} \

    #  Configure options based on processor architecture
     && if [ "`uname -m`" = "s390x" ]; then \
          with_luajit="--with-luajit=${LUAJIT_DIR}" ; \
          with_pcrejit="" ; \
        else \
          with_luajit="--with-luajit" ; \
          with_pcrejit="--with-pcrejit" ; \
        fi \

    #  Put this into a for loop so the other arguments didn't have to be
    #  kept in sync across multiple configure runs (a potential source of bugs)
     && for with_debug in '--with-debug' ''; do \
        echo " ... Building with debug flag value of '$with_debug'" \
        #  Use sh to run configure to avoid variable tokenization anxiety
        && sh -c "./configure \
            --prefix=${_exec_prefix}/api-gateway \
            --sbin-path=${_sbindir}/api-gateway-debug \
            --conf-path=${_sysconfdir}/api-gateway/api-gateway.conf \
            --error-log-path=${_localstatedir}/log/api-gateway/error.log \
            --http-log-path=${_localstatedir}/log/api-gateway/access.log \
            --pid-path=${_localstatedir}/run/api-gateway.pid \
            --lock-path=${_localstatedir}/run/api-gateway.lock \
            --add-module=../naxsi-${NAXSI_VERSION}/naxsi_src/ \
            --with-pcre=../pcre-${PCRE_VERSION}/ \
            $with_pcrejit \
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
            $with_luajit \
            --without-http_ssi_module \
            --without-http_userid_module \
            --without-http_uwsgi_module \
            --without-http_scgi_module \
            $debug \
            -j${NPROC}" \
        && make -j${NPROC} \
        && make install \
    ; done && echo " ... Done building OpenRESTY (both varieties)" \

    && echo "        - adding Nginx Test support" \
    && curl -k -L https://github.com/openresty/test-nginx/archive/v${TEST_NGINX_VERSION}.tar.gz -o ${_prefix}/test-nginx-${TEST_NGINX_VERSION}.tar.gz \
    && cd ${_prefix} \
    && tar -xf ${_prefix}/test-nginx-${TEST_NGINX_VERSION}.tar.gz \
    && rm ${_prefix}/test-nginx-${TEST_NGINX_VERSION}.tar.gz \
    && cp -r ${_prefix}/test-nginx-0.24/inc/* /usr/local/share/perl5/site_perl/ \

    && ln -s ${_sbindir}/api-gateway-debug ${_sbindir}/nginx \
    && cp /tmp/api-gateway/openresty-${OPENRESTY_VERSION}/build/install ${_prefix}/api-gateway/bin/resty-install \
    && rm -rf /tmp/api-gateway

ENV OPM_VERSION 0.0.3
RUN echo " ... installing opm..." \
    && mkdir -p /tmp/api-gateway \
    && curl -k -L https://github.com/openresty/opm/archive/v${OPM_VERSION}.tar.gz -o /tmp/api-gateway/opm-${OPM_VERSION}.tar.gz \
    && tar -xf /tmp/api-gateway/opm-${OPM_VERSION}.tar.gz -C /tmp/api-gateway \
    && cd /tmp/api-gateway/opm-${OPM_VERSION} \
    && cp bin/opm ${_prefix}/api-gateway/bin \
    && cd ${_prefix}/api-gateway \
    && mkdir -p site/manifest site/pod \
    && cd site \
    && ln -s ../lualib ./ \
    && ln -s ${_prefix}/api-gateway/bin/opm /usr/bin/opm \
    && ln -s ${_prefix}/api-gateway/bin/resty /usr/bin/resty \
    && rm -rf /tmp/api-gateway

#
#  TODO:  Clean this up so we aren't creating 11 additional layers.
#         Define all the ENV variables in one statement and run the
#         OPM gets as a command chain (or does OPM support multiple
#         packages in one get statement?

ENV LUA_RESTY_HTTP_VERSION=0.10 \
    LUA_RESTY_IPUTILS_VERSION=0.2.1 \
    LUA_RESTY_STRING_VERSION=0.09 \
    LUA_RESTY_LRUCACHE_VERSION=0.04 \
    LUA_RESTY_CJOSE_VERSION=0.3

RUN opm get \
     pintsized/lua-resty-http=${LUA_RESTY_HTTP_VERSION} \
     hamishforbes/lua-resty-iputils=${LUA_RESTY_IPUTILS_VERSION} \
     openresty/lua-resty-string=${LUA_RESTY_STRING_VERSION} \
     openresty/lua-resty-lrucache=${LUA_RESTY_LRUCACHE_VERSION} \
     taylorking/lua-resty-cjose=${LUA_RESTY_CJOSE_VERSION} \
     taylorking/lua-resty-rate-limit

ENV NETURL_LUA_VERSION 0.9-1
#  Tightened this up to pull the file directly out of the archive
RUN echo " ... installing neturl.lua ... " \
    && curl -sSL https://github.com/golgote/neturl/archive/${NETURL_LUA_VERSION}.tar.gz \
        | tar -zxf - -C ${_prefix}/api-gateway/lualib --strip-components=3 \
            neturl-${NETURL_LUA_VERSION}/lib/net/url.lua

ENV CJOSE_VERSION 0.5.1
RUN echo " ... installing cjose ... " \
    && mkdir -p /tmp/api-gateway \
    && curl -sSL https://github.com/cisco/cjose/archive/${CJOSE_VERSION}.tar.gz \
        | tar zxf - -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/cjose-${CJOSE_VERSION} \
    && sh configure \
    && make install \
    && rm -rf /tmp/api-gateway

RUN apk del build-deps

COPY init.sh /etc/init-container.sh
ONBUILD COPY init.sh /etc/init-container.sh
# add the default configuration for the Gateway
COPY . /etc/api-gateway
RUN adduser -S nginx-api-gateway \
    && addgroup -S nginx-api-gateway
ONBUILD COPY . /etc/api-gateway

EXPOSE 80 8080 8423 9000

#
#  The dumb-init is available as an Alpine package now, so its location has changed.
#
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/etc/init-container.sh"]
