#!/bin/sh
#
# Build both packages in throwaway containers, so the build host needs only
# Docker - no Ruby, no fpm, no rpm-build.

set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

for target in debian:deb rockylinux:rpm; do
  image=${target%:*}
  type=${target#*:}
  echo "==> building .$type in $image"
  docker build -q -t "icinga2-incident-io-build-$image" -f "build-linux/Dockerfile-$image" .
  docker run --rm -v "$HERE:/src" -w /src "icinga2-incident-io-build-$image" \
    ./build-linux/make_package.sh "$type"
done

echo
ls -l dist/
