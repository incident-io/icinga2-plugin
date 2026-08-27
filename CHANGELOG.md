# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Setup now points at the Icinga 2 alert source type in incident.io rather than
  a generic HTTP source. Accounts that predate it can still use an HTTP source:
  the handler sends the same payload either way, so nothing here depends on
  which one you pick.
- Example alert source URLs now use the `icinga2` path rather than `http`, and
  the install snippet no longer pins a version in the package filenames.

## [0.2.0] - 2026-08-26

### Added

- `IncidentIoIcingaWebStyle` selects the Icinga Web 2 front end that `source_url`
  points at: `icingadb` for Icinga DB Web, or `monitoring` for the older
  monitoring module. Previously only Icinga DB Web was addressable, so the link
  on every alert was a 404 for estates that have not migrated. Defaults to
  `icingadb`, and is read through `globals` so that leaving it unset is not a
  configuration error.
- `SECURITY.md` and `CONTRIBUTING.md`.

### Changed

- The Icinga Director basket now carries only the two custom variable fields,
  `incident_io` and `incident_io_metadata`. It previously shipped its own
  `Command`, `User` and `NotificationTemplate`, duplicating objects the package
  already installs to `conf.d` with versions that could not work: the command
  had no `env` block, so nothing reached the handler, and no notification was
  ever applied to a host or service. Director cannot set `env` on a command at
  all, so those objects were never going to be Director's to own. Setting
  `vars.incident_io` on Director-managed objects is the one thing Director is
  needed for, and that is what the fields do. The orphaned `DataList` is gone
  too; the boolean field never referenced it.

### Fixed

- `make basket` failed on a clean checkout, redirecting into a `dist/` directory
  that is gitignored and never created.
- `docs/TROUBLESHOOTING.md` told operators to run the handler as `nagios`.
  Icinga 2 runs as `icinga` on both Debian and RHEL families.
- The example payload in the README omitted `servicegroups`, which service
  alerts do carry.
- Repository URLs still pointed at `incident-io/icinga2`, including the
  `Homepage` field baked into every package.
- CI now checks that the version the handler reports matches the `VERSION`
  file. Only the file was checked against the tag, so a release could ship
  packages built as 0.2.0 whose `--version` and User-Agent still said 0.1.0.

## [0.1.0] - 2026-08-18

Initial release.

### Added

- `incident-io-icinga` notification handler: POSIX sh, no jq, Perl or Python.
- Host and service notification apply rules, opt-in per object via
  `vars.incident_io`.
- Arbitrary metadata passthrough via `vars.incident_io_metadata` and
  `vars.incident_io_metadata_vars`, encoded with Icinga's own `Json.encode()`,
  so nested dictionaries, arrays, numbers and booleans all survive intact.
- Estate-wide metadata defaults via `globals.IncidentIoDefaultMetadata`.
- `source_url` on each alert, linking back to the object in Icinga Web 2.
- Deduplication keyed on host and service name, so a RECOVERY resolves the alert
  its PROBLEM opened and the key is identical across HA masters.
- Notification type mapping, including resolving on `DOWNTIMESTART` so planned
  maintenance does not hold an alert open.
- Test suite covering escaping, metadata splicing, status mapping and
  portability across `sh`, `dash`, `bash` and `ksh`.
- `.deb` and `.rpm` packaging via fpm.
- Icinga Director basket generator, under `contrib/`.
- Release automation: pushing a `v*` tag publishes the built packages to GitHub
  Releases with notes from this file, and every merge to `main` refreshes a
  rolling `edge` prerelease whose packages are stamped `VERSION~git<date>.<sha>`
  so they sort before the tagged version and upgrade cleanly to it.
