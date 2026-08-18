# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `json_escape` returned an empty string for single-line values on POSIX and
  BSD `sed` (macOS, the BSDs). The final fold used `sed -e ':a' -e 'N'`, and
  POSIX `sed` quits without printing when `N` has no next line — so every
  escaped field came back empty, while multi-line values worked. Replaced the
  slurp with `awk`, which behaves identically on both userlands.
- `urlencode` passed an empty string as curl's URL argument, which curl 8
  rejects. Encodes against a dummy host and strips it back off.

### Changed

- Adds `awk` to the runtime dependencies.
- CI now runs the suite on macOS as well as Linux.

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
