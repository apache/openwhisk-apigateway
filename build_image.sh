#!/bin/bash

REPOSITORY=${REPOSITORY:-jpspring/s390x-openwhisk}

cd "$( dirname "${BASH_SOURCE[0]}" )" || exit

arch=$(docker info 2>/dev/null | sed -n 's/Architecture: \(.*\)/\1/p')
echo "Processing for $arch"

    tmpfile="$(mktemp -tp ".")"
    echo "...Pre-processing ./Dockerfile.m4 to $tmpfile"
    m4 -P \
      -D "$(echo "$arch" | tr '[:lower:]' '[:upper:]')" -D "m4_dockerarch=$arch" \
		  "./Dockerfile.m4" > $tmpfile

  echo "...Processing $tmpfile"

  label=$(grep '^#LABEL ' "$tmpfile" | sed -n 's/^#LABEL \(.*\)$/\1/p')
  docker build -t "$REPOSITORY:$label" -f "$tmpfile" . || {
    echo Failure building $1; exit 1
  }

  rm "$tmpfile"
  docker push "$REPOSITORY:$label"
