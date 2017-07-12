# apigateway
#
# VERSION               1.9.7.3
#
# From https://hub.docker.com/_/alpine/
#

FROM ubuntu:xenial

LABEL image_name=apigateway tags=1.11.2.2,1.11.2,1.11,latest

#
#  Pass the build an environment override for _profiling_on to activate profiling
#
ARG _profiling_on=
RUN apt-get update && sh -c "apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    file \
    gcc g++ \
    jq \
    libgeoip1 \
    libgeoip-dev \
    libjansson4 \
    libjansson-dev \
    libssl1.0.0 \
    libssl-dev \
    make \
    perl \
    ${_profiling_on:+elfutils systemtap systemtap-sdt-dev linux-headers-$(uname -r)}" \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN if [ -n "${_profiling_on}" ]; then : \
      && cp /proc/kallsyms /boot/System.map-`uname -r` \
      && mkdir -p /usr/local/share/perl5/site_perl /profiling/stapxx/FlameGraph \
      && curl -sSL https://api.github.com/repos/openresty/stapxx/tarball/master \
        | tar zxf - --strip-components=1 -C /profiling/stapxx\
      && curl -sSL https://api.github.com/repos/brendangregg/FlameGraph/tarball/master \
        | tar zxf - --strip-components=1 -C /profiling/stapxx/FlameGraph \
    ; fi

#
#  The S390X architecture needs a very specific patch to LuaJIT to work, so we
#  download andcompile it here for OpenRESTY to use later.  In the interests of
#  balancing workload across RUN stanzas, we always run this step.
#
ENV LUAJIT_VERSION=2.1.0-beta2 LUAJIT_DIR=/usr/local/api-gateway/luajit
RUN echo " ... compiling and installing LuaJIT" \
 && if [ "`uname -m`" = "s390x" ]; then \
     luajit_url="https://api.github.com/repos/linux-on-ibm-z/LuaJIT/tarball/tags/${LUAJIT_VERSION}" ; \
   else \
      luajit_url="http://luajit.org/download/LuaJIT-${LUAJIT_VERSION}.tar.gz" ; \
   fi \
 && mkdir -p /tmp/api-gateway/LuaJIT \
 && cd /tmp/api-gateway/LuaJIT \
 && echo 'Getting' "$luajit_url" \
 && curl -sSL "$luajit_url" \
    | tar zxf - --strip-components=1 \
 && make install PREFIX=${LUAJIT_DIR} \
 && rm -rf /tmp/api-gateway/LuaJIT

# openresty build
#ENV OPENRESTY_VERSION=1.9.7.3 \
ENV OPENRESTY_VERSION=1.11.2.2 \
     NAXSI_VERSION=0.53-2 \
     PCRE_VERSION=8.37 \
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
     && curl -sSL https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz | tar zfx - \
     && curl -sSL http://downloads.sourceforge.net/project/pcre/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.gz | tar zfx - \
     && curl -sSL https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz | tar zfx - \

     && cd /tmp/api-gateway/openresty-${OPENRESTY_VERSION} \

    #  Configure options based on processor architecture
     && if [ "`uname -m`" = "s390x" ]; then \
          with_pcrejit="" ; \
        else \
          with_pcrejit="--with-pcre-jit" ; \
        fi \

    #  Put this into a for loop so the other arguments didn't have to be
    #  kept in sync across multiple configure runs (a potential source of bugs)
     && for with_debug in '--with-debug' ''; do \
        echo " ... Building with debug flag value of '$with_debug'" \
        #  Use sh to run configure to avoid variable tokenization anxiety
        && sh -c "./configure \
            --prefix=${_exec_prefix}/api-gateway \
            --sbin-path=${_sbindir}/api-gateway${with_debug:+-debug} \
            --conf-path=${_sysconfdir}/api-gateway/api-gateway.conf \
            --error-log-path=${_localstatedir}/log/api-gateway/error.log \
            --http-log-path=${_localstatedir}/log/api-gateway/access.log \
            --pid-path=${_localstatedir}/run/api-gateway.pid \
            --lock-path=${_localstatedir}/run/api-gateway.lock \
            --add-module=../naxsi-${NAXSI_VERSION}/naxsi_src/ \
            --with-pcre=../pcre-${PCRE_VERSION}/ \
            ${with_pcrejit} \
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
            --with-luajit=${LUAJIT_DIR} \
            --without-http_ssi_module \
            --without-http_userid_module \
            --without-http_uwsgi_module \
            --without-http_scgi_module \
            ${with_debug} \
            ${_profiling_on:+--with-dtrace-probes} \
            -j${NPROC} \
            || { cat config.log; exit 1; }" \
        && make -j${NPROC} install \
    ; done && echo " ... Done building OpenRESTY (both varieties) ... " \

    && ln -s ${_sbindir}/api-gateway-debug ${_sbindir}/nginx \
    && cp /tmp/api-gateway/openresty-${OPENRESTY_VERSION}/build/install ${_prefix}/api-gateway/bin/resty-install \
    && rm -rf /tmp/api-gateway

ARG TEST_NGINX_VERSION=0.24
RUN echo "        - adding Nginx Test support" \
    && mkdir -p /usr/local/share/perl5/site_perl/ \
    && curl -sSL https://github.com/openresty/test-nginx/archive/v${TEST_NGINX_VERSION}.tar.gz \
      | tar zxfv - -C /usr/local/share/perl5/site_perl/ test-nginx-${TEST_NGINX_VERSION}/inc/ --strip-components=2 \
    && ls -lR /usr/local/share/perl5/site_perl

ARG OPM_VERSION=0.0.3
RUN echo " ... installing opm..." \
    && curl -sSL https://github.com/openresty/opm/archive/v${OPM_VERSION}.tar.gz  \
        | tar zxf - -C ${_prefix}/api-gateway/bin/ opm-${OPM_VERSION}/bin/opm --strip-components=1 \
    && mkdir -p ${_prefix}/api-gateway/site/manifest ${_prefix}/api-gateway/site/pod \
    && ln -s ${_prefix}/api-gateway/bin/opm /usr/bin/opm \
    && ln -s ${_prefix}/api-gateway/bin/resty /usr/bin/resty \
    && :

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

ARG NETURL_LUA_VERSION=0.9-1
#  Tightened this up to pull the file directly out of the archive
RUN echo " ... installing neturl.lua ... " \
    && curl -sSL https://github.com/golgote/neturl/archive/${NETURL_LUA_VERSION}.tar.gz \
        | tar -zxf - -C ${_prefix}/api-gateway/lualib --strip-components=3 \
            neturl-${NETURL_LUA_VERSION}/lib/net/url.lua

ARG CJOSE_VERSION=0.5.1
RUN echo " ... installing cjose ... " \
    && mkdir -p /tmp/api-gateway \
    && curl -sSL https://github.com/cisco/cjose/archive/${CJOSE_VERSION}.tar.gz \
        | tar zxf - -C /tmp/api-gateway/ \
    && cd /tmp/api-gateway/cjose-${CJOSE_VERSION} \
    && sh configure \
    && make install \
    && rm -rf /tmp/api-gateway

ARG DUMB_INIT_VERSION=1.2.0
RUN cd /tmp \
     && curl -sSLO https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_${DUMB_INIT_VERSION}_amd64.deb \
     && dpkg -i dumb-init_${DUMB_INIT_VERSION}_amd64.deb \
     && rm /tmp/dumb-init_1.2.0_amd64.deb

RUN apt-get purge -y \
  curl \
  file \
  gcc g++ \
  libgeoip-dev \
  libjansson-dev \
  libssl-dev \
  make \
 && apt-get autoremove -y \
 && apt-get clean
#RUN apk del build-deps

COPY init.sh /etc/init-container.sh
ONBUILD COPY init.sh /etc/init-container.sh
# add the default configuration for the Gateway
COPY . /etc/api-gateway
ONBUILD COPY . /etc/api-gateway

RUN adduser --system --group nginx-api-gateway

EXPOSE 80 8080 8423 9000

#
#  These lines will be automatically uncommented when building with
#  'make build-profile'
#
#PROFILE COPY ./api-gateway.conf.profiling /etc/api-gateway/api-gateway.conf
#PROFILE WORKDIR /tmp/stapxx

#
#  The dumb-init is available as a package now, so its location has changed.
#s
ENV LD_LIBRARY_PATH /usr/local/lib
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/etc/init-container.sh"]
