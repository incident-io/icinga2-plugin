#!/bin/sh
#
# Test suite for bin/incident-io-icinga.
#
# Runs the handler in --dry-run mode and asserts on the payload it builds, so
# nothing leaves the machine and no incident.io account is needed.
#
# Requires: python3 (test harness only - the handler itself needs none).
#
#   ./test/run-tests.sh            run against the default shell
#   SHELLS="sh dash bash" ./test/run-tests.sh   run against several shells

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
HANDLER="${HERE}/../bin/incident-io-icinga"
SHELLS="${SHELLS:-sh}"

PASS=0
FAIL=0

# assert <shell> <name> <jq-ish python expr> <expected>  (payload in $PAYLOAD)
assert() {
  _sh="$1"; _name="$2"; _expr="$3"; _want="$4"
  _got=$(printf '%s' "$PAYLOAD" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print($_expr)
" 2>&1) || _got="ERROR: $_got"

  if [ "$_got" = "$_want" ]; then
    PASS=$((PASS + 1))
    printf '  ok   [%s] %s\n' "$_sh" "$_name"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL [%s] %s\n       want: %s\n       got:  %s\n' "$_sh" "$_name" "$_want" "$_got"
  fi
}

assert_valid_json() {
  _sh="$1"
  if printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    PASS=$((PASS + 1)); printf '  ok   [%s] payload is valid JSON\n' "$_sh"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL [%s] payload is NOT valid JSON\n       %s\n' "$_sh" "$PAYLOAD"
  fi
}

# Constant for every case, so export rather than passing through env - an
# unquoted "$BASE_ENV" would rely on word splitting, which shellcheck flags
# and which breaks on any value containing a space.
INCIDENT_IO_URL="https://example.invalid/alert"
INCIDENT_IO_TOKEN="test-token"
export INCIDENT_IO_URL INCIDENT_IO_TOKEN

run_suite() {
  SH="$1"
  printf '\n== %s ==\n' "$SH"

  # -- 1. hostile characters in output and service name -------------------
  PAYLOAD=$(env \
    HOST_NAME='web-01.dc-fra' \
    SERVICE_NAME='disk C:\ "root"' \
    STATE='CRITICAL' \
    NOTIFICATION_TYPE='PROBLEM' \
    CHECK_SOURCE='satellite-fra-1' \
    OUTPUT='DISK CRITICAL - C:\Users 12% (quote " backslash \ tab	x)
line two
| free=93%;80;90' \
    "$SH" "$HANDLER" --dry-run)

  assert_valid_json "$SH"
  assert "$SH" 'escapes quotes and backslashes' \
    "d['metadata']['service']" 'disk C:\ "root"'
  assert "$SH" 'folds multi-line output' \
    "repr(d['description'].count(chr(10)))" '2'
  assert "$SH" 'service dedup key' \
    "d['deduplication_key']" 'icinga/web-01.dc-fra/disk C:\ "root"'
  assert "$SH" 'problem is firing' "d['status']" 'firing'
  assert "$SH" 'carries check_source' "d['metadata']['check_source']" 'satellite-fra-1'

  # -- 2. host notification, recovery -------------------------------------
  PAYLOAD=$(env -u SERVICE_NAME \
    HOST_NAME='db-02' STATE='UP' NOTIFICATION_TYPE='RECOVERY' \
    OUTPUT='PING OK - Packet loss = 0%, RTA = 0.42 ms' \
    "$SH" "$HANDLER" --dry-run)

  assert "$SH" 'host dedup key' "d['deduplication_key']" 'icinga/db-02/_host'
  assert "$SH" 'host title' "d['title']" 'db-02 is UP'
  assert "$SH" 'recovery resolves' "d['status']" 'resolved'

  # -- 3. status mapping --------------------------------------------------
  for pair in 'PROBLEM firing' 'RECOVERY resolved' 'ACKNOWLEDGEMENT firing' \
              'DOWNTIMESTART resolved' 'DOWNTIMEEND firing' \
              'FLAPPINGSTART firing' 'FLAPPINGEND resolved'; do
    t=${pair% *}; want=${pair#* }
    PAYLOAD=$(env HOST_NAME=h SERVICE_NAME=s STATE=CRITICAL \
      NOTIFICATION_TYPE="$t" OUTPUT=x "$SH" "$HANDLER" --dry-run)
    assert "$SH" "status mapping $t" "d['status']" "$want"
  done

  # -- 4. flexible metadata: nested objects, arrays, numbers, booleans -----
  PAYLOAD=$(env HOST_NAME=h SERVICE_NAME=s STATE=CRITICAL \
    NOTIFICATION_TYPE=PROBLEM OUTPUT=x \
    INCIDENT_IO_METADATA_JSON='{"team":"payments","tier":1,"oncall":true,"hostgroups":["prod","linux"],"owner":{"squad":"core","slack":"#pay-alerts"}}' \
    "$SH" "$HANDLER" --dry-run)

  assert_valid_json "$SH"
  assert "$SH" 'metadata: string passthrough'  "d['metadata']['team']" 'payments'
  assert "$SH" 'metadata: number preserved'    "repr(d['metadata']['tier'])" '1'
  assert "$SH" 'metadata: boolean preserved'   "repr(d['metadata']['oncall'])" 'True'
  assert "$SH" 'metadata: array preserved'     "','.join(d['metadata']['hostgroups'])" 'prod,linux'
  assert "$SH" 'metadata: nested object'       "d['metadata']['owner']['slack']" '#pay-alerts'
  assert "$SH" 'metadata: built-ins survive'   "d['metadata']['source']" 'icinga'

  # -- 5. metadata with hostile values ------------------------------------
  PAYLOAD=$(env HOST_NAME=h SERVICE_NAME=s STATE=CRITICAL \
    NOTIFICATION_TYPE=PROBLEM OUTPUT=x \
    INCIDENT_IO_METADATA_JSON='{"note":"has \"quotes\" and a \\ backslash","path":"C:\\Windows"}' \
    "$SH" "$HANDLER" --dry-run)

  assert_valid_json "$SH"
  assert "$SH" 'metadata: escaped quotes intact' \
    "d['metadata']['note']" 'has "quotes" and a \ backslash'

  # -- 6. operator keys override built-ins --------------------------------
  PAYLOAD=$(env HOST_NAME=h SERVICE_NAME=s STATE=CRITICAL \
    NOTIFICATION_TYPE=PROBLEM OUTPUT=x \
    INCIDENT_IO_METADATA_JSON='{"source":"icinga-eu"}' \
    "$SH" "$HANDLER" --dry-run)
  assert "$SH" 'metadata: operator key wins' "d['metadata']['source']" 'icinga-eu'

  # -- 7. malformed / empty metadata is survivable ------------------------
  for bad in '' '{}' 'null' 'not json at all' '["an","array"]'; do
    PAYLOAD=$(env HOST_NAME=h SERVICE_NAME=s STATE=CRITICAL \
      NOTIFICATION_TYPE=PROBLEM OUTPUT=x INCIDENT_IO_METADATA_JSON="$bad" \
      "$SH" "$HANDLER" --dry-run 2>/dev/null)
    assert_valid_json "$SH"
  done

  # -- 8. source_url ------------------------------------------------------
  PAYLOAD=$(env HOST_NAME='web 01' SERVICE_NAME='disk /' STATE=CRITICAL \
    NOTIFICATION_TYPE=PROBLEM OUTPUT=x \
    ICINGAWEB_URL='https://icinga.example.com/icingaweb2/' \
    "$SH" "$HANDLER" --dry-run)
  assert "$SH" 'source_url is url-encoded' "d['source_url']" \
    'https://icinga.example.com/icingaweb2/icingadb/service?name=disk+%2F&host.name=web+01'

  PAYLOAD=$(env HOST_NAME=h SERVICE_NAME=s STATE=CRITICAL \
    NOTIFICATION_TYPE=PROBLEM OUTPUT=x "$SH" "$HANDLER" --dry-run)
  assert "$SH" 'source_url empty without base' "d['source_url']" ''

  # -- 9. acknowledgement comment ----------------------------------------
  PAYLOAD=$(env HOST_NAME=h SERVICE_NAME=s STATE=CRITICAL \
    NOTIFICATION_TYPE=ACKNOWLEDGEMENT NOTIFICATION_AUTHOR=rloffelmacher \
    NOTIFICATION_COMMENT='looking into it' OUTPUT='CRITICAL - 100% packet loss' \
    "$SH" "$HANDLER" --dry-run)
  assert "$SH" 'ack comment appended' \
    "'looking into it' in d['description']" 'True'
}

# --- config error handling (shell-independent) ---------------------------
printf '\n== configuration errors ==\n'
check_exit() {
  _name="$1"; _want="$2"; shift 2
  "$@" >/dev/null 2>&1 && _got=0 || _got=$?
  if [ "$_got" = "$_want" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s (exit %s)\n' "$_name" "$_got"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s: want exit %s, got %s\n' "$_name" "$_want" "$_got"
  fi
}
check_exit 'missing URL exits 2'   2 env -u INCIDENT_IO_URL INCIDENT_IO_TOKEN=t HOST_NAME=h sh "$HANDLER" --dry-run
check_exit 'missing token exits 2' 2 env -u INCIDENT_IO_TOKEN INCIDENT_IO_URL=u HOST_NAME=h sh "$HANDLER" --dry-run
check_exit 'missing host exits 2'  2 env -u HOST_NAME INCIDENT_IO_URL=u INCIDENT_IO_TOKEN=t sh "$HANDLER" --dry-run
check_exit 'bad argument exits 2'  2 env INCIDENT_IO_URL=u INCIDENT_IO_TOKEN=t HOST_NAME=h sh "$HANDLER" --nope
check_exit '--version exits 0'     0 sh "$HANDLER" --version

for s in $SHELLS; do
  if command -v "$s" >/dev/null 2>&1; then
    run_suite "$s"
  else
    printf '\n== %s == (not installed, skipped)\n' "$s"
  fi
done

printf '\n---\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
