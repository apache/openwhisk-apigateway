#!/bin/bash

set -euo pipefail

#
#  The profiling setup will have dtrace installed, so
#  we should use it in the configuration
#
if command -v dtrace; then
    debug_options="--with-debug --with-dtrace-probes"
else
    debug_options="--with-debug"
fi

#
#  The api-gateway.conf file should have been copied and will likely tell us
#  whether to install PCRE JIT
#
if grep 'pcre_jit *yes' /etc/api-gateway/api-gateway.conf; then
    with_pcre_jit="--with-pcre-jit"
else
    with_pcre_jit=""
fi

case "$(uname -m)" in
    s390x)
         echo "Building LuaJIT for s390x"
         curl -sSL https://api.github.com/repos/linux-on-ibm-z/LuaJIT/tarball/v2.1 \
         | tar -C /tmp -zxf -
         (cd /tmp/linux-on-ibm-z-LuaJIT-* && make install)
         rm -rf /tmp/luajit.tar.gz /tmp/linux-on-ibm-z-LuaJIT-*
         luajitdir="=/usr/local/"
         ;;
    ppc64le)
        echo "Building LuaJIT for ppc64le"
        curl -sSL https://api.github.com/repos/PPC64/LuaJIT/tarball \
        | tar -C /tmp -zxf -
        (cd /tmp/PPC64-LuaJIT-* && make install)
        rm -rf /tmp/luajit.tar.gz /tmp/PPC64-LuaJIT-*
        luajitdir="=/usr/local/"
        ;;
    *)
        echo "Configuring for $(uname -m)"
        luajitdir=""
        ;;
esac

echo " ... adding Openresty, NGINX, NAXSI and PCRE"
mkdir -p /tmp/api-gateway
readonly NPROC="$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1)"
echo "using up to $NPROC threads"

curl -sSL "https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz" \
    | tar -C /tmp/api-gateway -zxf -

curl -sSL "https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz" \
    | tar -C /tmp/api-gateway -zxf -

curl -sSL "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz" \
    | tar -C /tmp/api-gateway -zxf -

echo "        - building debugging version of the api-gateway ... "
for with_debug in "$debug_options" ""; do (
    cd "/tmp/api-gateway/openresty-${OPENRESTY_VERSION}"
    echo "Building with debug options '$with_debug'"
    ./configure \
            --prefix="${_exec_prefix}/api-gateway" \
            --sbin-path="${_sbindir}/api-gateway-debug" \
            --conf-path="${_sysconfdir}/api-gateway/api-gateway.conf" \
            --error-log-path="${_localstatedir}/log/api-gateway/error.log" \
            --http-log-path="${_localstatedir}/log/api-gateway/access.log" \
            --pid-path="${_localstatedir}/run/api-gateway.pid" \
            --lock-path="${_localstatedir}/run/api-gateway.lock" \
            --add-module="../naxsi-${NAXSI_VERSION}/naxsi_src/" \
            --with-pcre="../pcre-${PCRE_VERSION}/" \
            $with_pcre_jit \
            --with-stream \
            --with-stream_ssl_module \
            --with-http_ssl_module \
            --with-http_stub_status_module \
            --with-http_realip_module \
            --with-http_addition_module \
            --with-http_sub_module \
            --with-http_dav_module \
            --with-http_geoip_module \
            --with-http_gunzip_module \
            --with-http_gzip_static_module \
            --with-http_auth_request_module \
            --with-http_random_index_module \
            --with-http_secure_link_module \
            --with-http_degradation_module \
            --with-http_auth_request_module \
            --with-http_v2_module \
            "--with-luajit${luajitdir}" \
            --without-http_ssi_module \
            --without-http_userid_module \
            --without-http_uwsgi_module \
            --without-http_scgi_module \
            $with_debug \
            "-j$NPROC"
    make "-j$NPROC" install
); done

mkdir -p "${_prefix}/api-gateway/bin"
cp "/tmp/api-gateway/openresty-${OPENRESTY_VERSION}/build/install" \
    "${_prefix}/api-gateway/bin/resty-install"
rm -rf /tmp/api-gateway

# VIM: let b:syntastic_sh_shellcheck_args = "-e SC2154"
