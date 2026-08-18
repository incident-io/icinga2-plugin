#!/bin/sh
#
# Build a .deb or .rpm using fpm.
#
#   ./build-linux/make_package.sh deb
#   ./build-linux/make_package.sh rpm
#
# fpm: gem install fpm   (rpm builds also need rpm-build / rpmdevtools)

set -eu

TYPE="${1:-}"
case "$TYPE" in
  deb|rpm) ;;
  *) echo "usage: $0 {deb|rpm}" >&2; exit 2 ;;
esac

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

VERSION=$(cat VERSION)
STAGE="build/stage"
OUT="dist"

command -v fpm >/dev/null 2>&1 || { echo "fpm not found: gem install fpm" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/usr/bin" \
         "$STAGE/etc/icinga2/zones.d/master" \
         "$STAGE/etc/icinga2/conf.d" \
         "$STAGE/usr/share/doc/icinga2-incident-io" \
         "$OUT"

install -m 0755 bin/incident-io-icinga                  "$STAGE/usr/bin/"
install -m 0644 conf.d/incident-io-command.conf         "$STAGE/etc/icinga2/zones.d/master/"
install -m 0644 conf.d/incident-io-notifications.conf   "$STAGE/etc/icinga2/zones.d/master/"
install -m 0644 conf.d/incident-io-secrets.conf.example "$STAGE/etc/icinga2/conf.d/"
install -m 0644 README.md LICENSE                       "$STAGE/usr/share/doc/icinga2-incident-io/"
cp -r docs                                              "$STAGE/usr/share/doc/icinga2-incident-io/"

# The .conf files are config, not program data - mark them so upgrades don't
# stomp local edits.
fpm -s dir -t "$TYPE" \
  -n icinga2-incident-io \
  -v "$VERSION" \
  --description "Forward Icinga 2 notifications to incident.io" \
  --url "https://github.com/incident-io/icinga2" \
  --maintainer "incident.io <support@incident.io>" \
  --license "MIT" \
  --architecture all \
  --depends curl \
  --config-files /etc/icinga2/zones.d/master/incident-io-command.conf \
  --config-files /etc/icinga2/zones.d/master/incident-io-notifications.conf \
  --config-files /etc/icinga2/conf.d/incident-io-secrets.conf.example \
  --after-install build-linux/postinst \
  --package "$OUT/" \
  -C "$STAGE" .

echo
ls -l "$OUT"
