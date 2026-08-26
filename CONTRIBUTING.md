# Contributing

Bug reports, questions and patches are all welcome.

## Reporting a bug

Open an issue with your Icinga 2 version, your platform, and the output of
`incident-io-icinga --version`. The most useful thing you can attach is the
payload the handler built:

```sh
INCIDENT_IO_URL=x INCIDENT_IO_TOKEN=x \
HOST_NAME=web-01 SERVICE_NAME='disk /' STATE=CRITICAL \
NOTIFICATION_TYPE=PROBLEM OUTPUT='DISK CRITICAL - 12% free' \
  incident-io-icinga --dry-run
```

`--dry-run` sends nothing. Check it for anything you would rather not post in
public before you attach it, and never include your alert source token.

For security issues, see [SECURITY.md](SECURITY.md) instead.

## Working on the code

```sh
make test     # run the test suite across sh, dash and bash
make lint     # shellcheck
```

Tests run the handler in `--dry-run` and assert on the payload, so they need no
network access and no incident.io account. They do need `python3`, which the
handler itself does not.

CI additionally runs the suite under `ksh`, against `mawk` and `busybox awk`,
with GNU `sed` forced into POSIX mode, and on macOS for BSD userland. That last
one earns its place: the handler is POSIX `sh`, and the one bug that reached a
release was a GNU `sed` extension that returned an empty string everywhere else.
`make test-posix` reproduces the POSIX `sed` behaviour on a GNU box.

Please add a test with any change to the payload the handler builds.

## Things worth knowing

**The handler must stay dependency-free.** POSIX `sh` plus the coreutils that
ship in a base install. Reaching for `jq`, Perl or Python would mean asking
operators to install something on every Icinga master, which is a much bigger
ask than it looks. That constraint is the reason for the hand-rolled JSON
escaping and URL encoding.

**The deduplication key derives only from object names.** Never put a state, a
timestamp or the sending node in it. That is what lets a RECOVERY resolve the
alert its PROBLEM opened, and what keeps HA masters from opening two alerts.

**Configuration installs to `conf.d`, not `zones.d`.** Constants defined in
`conf.d` are invisible to config synced from `zones.d`, and zone sync cannot
distribute the handler binary anyway. See
[docs/DISTRIBUTED.md](docs/DISTRIBUTED.md).

## Support

This repository covers the integration itself. For anything about your
incident.io account, email support@incident.io.
