#!/bin/bash

#
#  Repository to which the image should be saved.  I'm open to suggestions
#  for how to make this more universal -JPS
#
REPOSITORY=${REPOSITORY:-jpspring/s390x-openwhisk}

cd "$( dirname "${BASH_SOURCE[0]}" )" || exit

arch=$(docker info 2>/dev/null | sed -n 's/Architecture: \(.*\)/\1/p')
echo "Processing for $arch"

#  This is where the magic happens.  M4 is an old macro processor that
#  we feed symbols to trigger inclusion/exclusion of certain code
tmpfile="$(mktemp -tp ".")"
echo "...Pre-processing ./Dockerfile.m4 to $tmpfile"
m4 -P \
-D "$(echo "$arch" | tr '[:lower:]' '[:upper:]')" -D "m4_dockerarch=$arch" \
	  "./Dockerfile.m4" > $tmpfile

echo "...Processing $tmpfile"

#
#  Similarly, this is the label being pulled out of a comment in the image.
#  Perhaps it should be metadata or an Environment variable.
#
label=$(grep '^#LABEL ' "$tmpfile" | sed -n 's/^#LABEL \(.*\)$/\1/p')
docker build -t "$REPOSITORY:$label" -f "$tmpfile" . || {
echo Failure building $1; exit 1
}

rm "$tmpfile"
docker push "$REPOSITORY:$label"
