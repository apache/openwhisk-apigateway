#!/bin/bash

#  Bash 4 lets us run the last pipe command in the current context,
#  which eases error testing and reading stdout.
shopt -s lastpipe

DOCKER_REGISTRY=${DOCKER_REGISTRY:-docker.xanophis.com}

cd "$( dirname "${BASH_SOURCE[0]}" )" || exit

arch=$(docker info 2>/dev/null | sed -n 's/Architecture: \(.*\)/\1/p')
echo "Processing for $arch"

process_dockerfile() {

  cd $1 || exit

  if [ "$arch" = "x86_64" ]; then
    sedcmd="";
  else
    sedcmd="s!^FROM alpine!FROM $arch/alpine!"
  fi

  #label=$(grep '^#LABEL ' "$dockerfile" | sed -n 's/^#LABEL \(.*\)$/\1/p')
  tmpfile=$(mktemp -p "$1")
  sed -e "$sedcmd" <Dockerfile >"$tmpfile"
  docker build -t "t_$$" -f "$tmpfile" "$1" || {
    echo Failure building $1; exit 1
  }
  [ -n "$tmpfile" ] && rm "$tmpfile"

  #  TODO:  Fail gracefully if the LABELs weren't set up properly
  docker inspect "t_$$" \
    | jq -r '.[].Config.Labels.image_name,.[].Config.Labels.tags' \
    | { read image_name; IFS=',' read -a tags; }

  echo "image_name=" $image_name
  echo "tags=" "${tags[@]}"

  for i in "$(dirname $1)"/test_*; do
    if [[ -x "$i" ]]; then eval "$i"; fi
  done

  for tag in "${tags[@]}"; do
    docker tag "t_$$" "$DOCKER_REGISTRY/$arch/$image_name:$tag"
    docker push "$DOCKER_REGISTRY/$arch/$image_name:$tag"
  done

  docker rmi "t_$$"  # Remove the temporary tag
}

process_dockerfile .
