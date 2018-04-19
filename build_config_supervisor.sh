#ENV CONFIG_SUPERVISOR_VERSION 1.0.1-RC1
export GOPATH=/usr/lib/go/bin
export GOBIN=/usr/lib/go/bin
export PATH=$PATH:/usr/lib/go/bin
echo " ... installing api-gateway-config-supervisor  ... " \
apk update 
apk add gcc make git go 
mkdir -p /tmp/api-gateway 
curl -k -L https://github.com/adobe-apiplatform/api-gateway-config-supervisor/archive/${CONFIG_SUPERVISOR_VERSION}.tar.gz -o /tmp/api-gateway/api-gateway-config-supervisor-${CONFIG_SUPERVISOR_VERSION}.tar.gz 
cd /tmp/api-gateway
tar -xf /tmp/api-gateway/api-gateway-config-supervisor-${CONFIG_SUPERVISOR_VERSION}.tar.gz
mkdir -p /tmp/go
mv /tmp/api-gateway/api-gateway-config-supervisor-${CONFIG_SUPERVISOR_VERSION}/* /tmp/go
cd /tmp/go
make setup
mkdir -p /tmp/go/Godeps/_workspace
ln -s /tmp/go/vendor /tmp/go/Godeps/_workspace/src
mkdir -p /tmp/go-src/src/github.com/adobe-apiplatform
ln -s /tmp/go /tmp/go-src/src/github.com/adobe-apiplatform/api-gateway-config-supervisor
GOPATH=/tmp/go/vendor:/tmp/go-src CGO_ENABLED=0 GOOS=linux /usr/lib/go/bin/godep  go build -ldflags "-s" -a -installsuffix cgo -o api-gateway-config-supervisor ./
mv /tmp/go/api-gateway-config-supervisor /usr/local/sbin/

echo "installing rclone sync ... " 
go get github.com/ncw/rclone
mv /usr/lib/go/bin/rclone /usr/local/sbin/ 
mkdir -p /root/.config/rclone/
cat <<EOF > /root/.config/rclone/rclone.conf
[local] 
type = local 
nounc = true
EOF

echo " cleaning up ... " 
rm -rf /usr/lib/go/bin/src
rm -rf /tmp/go
rm -rf /tmp/go-src
rm -rf /usr/lib/go/bin/pkg/
rm -rf /usr/lib/go/bin/godep
apk del make git go gcc
rm -rf /var/cache/apk/*