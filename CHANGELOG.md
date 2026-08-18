# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-18

### Added

- `incident-io-icinga` notification handler: POSIX sh, no jq/perl/python.
- Host and service notification apply rules, opt-in via `vars.incident_io`.
- Arbitrary metadata passthrough via `vars.incident_io_metadata` and
  `vars.incident_io_metadata_vars`, encoded with Icinga's own `Json.encode()`.
- `source_url` linking each alert back to Icinga Web 2 / Icinga DB Web.
- Deduplication keyed on host + service, stable across HA masters.
- Test suite covering escaping, metadata splicing, status mapping and
  portability across `sh`, `dash`, `bash` and `ksh`.
- `.deb` and `.rpm` packaging via fpm, with Docker-based builds.
- Contrib: Icinga Director basket generator.
- Pushing a `v*` tag publishes the built packages as a GitHub release, with
  notes taken from this file. Every merge to `main` refreshes a rolling `edge`
  prerelease, whose packages are stamped `VERSION~git<date>.<sha>` so they sort
  before the tagged version and upgrade cleanly to it.

### Fixed

- `json_escape` returned an empty string for single-line values on POSIX and
  BSD `sed` (macOS, the BSDs). The final fold used `sed -e ':a' -e 'N'`, and
  POSIX `sed` quits without printing when `N` has no next line, so every
  escaped field came back empty while multi-line values worked. Replaced the
  slurp with `awk`, which behaves identically on both userlands.
- `urlencode` passed an empty string as curl's URL argument, which curl 8
  rejects. Encodes against a dummy host and strips it back off.
- Metadata values were macro-expanded a second time. Icinga runs macro
  resolution over the value it substitutes into the command's `env` block, so a
  custom variable holding `$host.name$` arrived at the handler as the host's
  name, and `$$` collapsed to `$`. Since that pass runs in the notification's
  own macro context it could reach any attribute visible there. The builder now
  escapes each `$` as `$$`, which Icinga's own unescaping reverses.
- `period = "24x7"` on the contact and the notification template made the
  integration depend on the stock `conf.d/timeperiods.conf`. Where that
  TimePeriod is absent, Icinga does not degrade: it aborts the whole config
  load, so installing this took down all of Icinga rather than just alerting.
  An unset period already means "no time restriction", so the attribute is
  gone.
- `METADATA.md` and `TROUBLESHOOTING.md` told operators to check metadata with
  a bare `icinga2 console`, which cannot work: that console does not load the
  configuration, so the function is undefined there. Documents
  `icinga2 console --connect` instead.

### Verified

- Request schema checked against the incident.io OpenAPI specification for
  `POST /v2/alert_events/http/{alert_source_config_id}`: `title` and `status`
  are the only required fields, `status` is an enum of `firing` and `resolved`,
  and `metadata` is a free-form object. All fields sent by the handler match.
- The `conf.d/` configuration now runs against a live Icinga 2.16.5, from
  `icinga2 daemon -C` through to a captured HTTP POST whose body is
  byte-identical to `--dry-run` for the same object. Covers host and service
  paths, the opt-in and opt-out matrix, metadata layering and overrides,
  PROBLEM, RECOVERY, ACKNOWLEDGEMENT, CUSTOM and downtime notifications, and
  oversized metadata. It also parses on 2.12.12. Distributed behaviour
  (satellite `check_source`, zone config sync, HA notification failover) is
  still unverified.

### Changed

- Config now installs to `/etc/icinga2/conf.d/` rather than
  `/etc/icinga2/zones.d/master/`. Constants defined in `conf.d` are not visible
  to configuration synced from `zones.d`, so the previous layout would have
  failed validation on `IncidentIoUrl`. Zone sync cannot distribute the handler
  binary anyway, so per-master installation was already required.
- Adds `awk` and `od` to the runtime dependencies.
- CI now runs the suite on macOS as well as Linux.
- `build-linux/make_package.sh` honours `PKG_VERSION`, overriding the `VERSION`
  file, so CI can stamp pre-release builds.

