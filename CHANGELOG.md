# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-18

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
