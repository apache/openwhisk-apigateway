#!/bin/bash

#  This script is a hack of sorts to support multi-architecture builds,
#  specifically for the s390x (LinuxOne) architecture.  It will likely
#  be necessary to add additional supported architectures as the project
#  branches out.

cd "$( dirname "${BASH_SOURCE[0]}" )" || exit

arch=$(docker info 2>/dev/null | sed -n 's/Architecture: \(.*\)/\1/p')
echo "Processing for $arch"

#  Tmpfile management -- global so we can trap exits and clean up
tmpfile=""
finish() {
  [ -n "$tmpfile" ] && rm "$tmpfile"
}
trap finish EXIT

#  When building on non-x86_64 architectures, it's necessary
#  to tinker with the FROM line in the Dockerfile.  I fear
#  this is going to become a massive case statement.
if [ "$arch" = "s390x" ]; then
  sedcmd="s!^FROM alpine!FROM $arch/alpine!"
else sedcmd=""; fi

#  TODO -- take the tag to build as a script argument
tmpfile=$(mktemp "./tmp.Dockerfile.XXXXXXXX")
sed -e "$sedcmd" <./Dockerfile >"$tmpfile"
docker build -t "t_$$" -f "$tmpfile" .
