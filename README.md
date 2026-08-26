# incident.io for Icinga 2

Sends Icinga 2 host and service notifications to an incident.io HTTP alert
source, and resolves them on recovery.

## Requirements

| | |
| --- | --- |
| Icinga 2 | 2.11 or newer |
| On each master | POSIX `/bin/sh`, `curl`, `sed`, `awk`, `tr`, `od`, `mktemp` |
| Network | outbound HTTPS from each master to `api.incident.io` |
| Optional | `logger`, to send handler output to syslog |

Everything but `curl` is in the base install of any Linux distribution. There is
no `jq`, Perl or Python dependency.

## How it works

The integration is a `NotificationCommand` — Icinga invokes
`/usr/bin/incident-io-icinga` when a notification fires, and the handler POSTs
a JSON payload to your alert source.

This has three consequences:

1. **Masters only.** Notifications fire from the master zone, so the package is
   installed on masters and nothing else. Satellites and agents are unaffected,
   and only the masters need egress.
2. **Icinga's suppression applies first.** Downtimes, acknowledgements,
   notification periods and `times` windows are evaluated by Icinga before the
   handler runs. Objects in downtime do not generate alerts.
3. **Opt-in.** Installing the package changes no behaviour until objects are
   marked with `vars.incident_io = true`.

## Installation

Install on every master in the master zone. Icinga's config sync distributes
`.conf` files but not the handler binary, so each master needs the package.

**Package:**

```sh
# Debian / Ubuntu
sudo apt install ./icinga2-incident-io_0.1.0_all.deb

# RHEL / Rocky / SLES
sudo rpm -i icinga2-incident-io-0.1.0-1.noarch.rpm
```

**Source:**

```sh
git clone https://github.com/incident-io/icinga2.git
cd icinga2
sudo make install
```

Installed files:

| Path | Purpose |
| --- | --- |
| `/usr/bin/incident-io-icinga` | Notification handler |
| `/etc/icinga2/conf.d/incident-io-command.conf` | `NotificationCommand`, contact, metadata builder |
| `/etc/icinga2/conf.d/incident-io-notifications.conf` | Apply rules |
| `/etc/icinga2/conf.d/incident-io-secrets.conf.example` | Credentials template |

## Configuration

### 1. Create an alert source

In incident.io: **Settings → Alerts → Sources → New source → HTTP.** Note the
URL and bearer token.

### 2. Add credentials

On each master:

```sh
sudo cp /etc/icinga2/conf.d/incident-io-secrets.conf.example \
        /etc/icinga2/conf.d/incident-io-secrets.conf
sudo chown root:icinga /etc/icinga2/conf.d/incident-io-secrets.conf
sudo chmod 0640        /etc/icinga2/conf.d/incident-io-secrets.conf
sudoedit /etc/icinga2/conf.d/incident-io-secrets.conf
```

```
const IncidentIoUrl          = "https://api.incident.io/v2/alert_events/http/SOURCE_ID"
const IncidentIoToken        = "TOKEN"
const IncidentIoIcingaWebUrl = "https://icinga.example.com/icingaweb2"

globals.IncidentIoIcingaWebStyle = "icingadb"   // or "monitoring"
```

`IncidentIoIcingaWebStyle` decides which Icinga Web 2 front end the `source_url`
on each alert points at: `icingadb` for Icinga DB Web, the current default, or
`monitoring` for the older monitoring module. Open a host in Icinga Web 2 and
look at the URL if you are unsure. Leave it out and you get `icingadb`.

Everything installs to `conf.d`, on every master, rather than being distributed
by zone sync from `zones.d`. Constants defined in `conf.d` are not visible to
configuration synced from `zones.d`, and the handler binary has to be installed
per-master regardless. See [docs/DISTRIBUTED.md](docs/DISTRIBUTED.md).

### 3. Select objects

```
object Host "web-01.dc-fra" {
  import "generic-host"
  address = "10.0.1.4"

  vars.incident_io = true      // this host and its services
}
```

To exclude a service on an otherwise included host, set
`vars.incident_io = false` on the service. To route the entire estate, change
the `assign where` clauses in `incident-io-notifications.conf` to
`assign where true`.

### 4. Reload

```sh
sudo icinga2 daemon -C && sudo systemctl reload icinga2
```

## Verification

Print a payload without sending it:

```sh
INCIDENT_IO_URL=x INCIDENT_IO_TOKEN=x \
HOST_NAME=web-01 SERVICE_NAME='disk /' STATE=CRITICAL \
NOTIFICATION_TYPE=PROBLEM OUTPUT='DISK CRITICAL - 12% free' \
  incident-io-icinga --dry-run
```

Then send a live notification from Icinga Web 2 using **Send custom
notification** on any selected object.

Handler output goes to syslog under the tag `incident-io-icinga`. Exit codes:
`0` delivered, `1` delivery failed, `2` configuration error. See
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

As with any change to notification routing, we recommend opting in a handful of
objects, or a non-production zone, and watching the alerts arrive before you
enable it across the estate. The `vars.incident_io` opt-in is designed to make
that easy.

## Payload

```json
{
  "title": "disk / on web-01.dc-fra is CRITICAL",
  "description": "DISK CRITICAL - free space: / 1.2GB (12% inode=98%)",
  "deduplication_key": "icinga/web-01.dc-fra/disk /",
  "status": "firing",
  "source_url": "https://icinga.example.com/icingaweb2/icingadb/service?name=disk+%2F&host.name=web-01.dc-fra",
  "metadata": {
    "host": "web-01.dc-fra",
    "service": "disk /",
    "state": "CRITICAL",
    "notification_type": "PROBLEM",
    "check_source": "satellite-fra-1",
    "hostgroups": ["linux", "prod"],
    "servicegroups": ["disk"],
    "source": "icinga"
  }
}
```

`deduplication_key` is derived from host and service names only — never from
state, timestamp or sending node. This is what allows a RECOVERY to resolve the
alert its PROBLEM opened, keeps re-notifications from creating duplicates, and
makes the key identical across HA masters.

`metadata` is extensible. Any Icinga custom variable, including nested
dictionaries and arrays, can be attached and used for routing in incident.io.
See [docs/METADATA.md](docs/METADATA.md).

## Notification type mapping

| Icinga type | Alert status | Note |
| --- | --- | --- |
| `PROBLEM` | `firing` | |
| `RECOVERY` | `resolved` | |
| `ACKNOWLEDGEMENT` | `firing` | Author and comment appended to description |
| `CUSTOM` | `firing` | |
| `FLAPPINGSTART` | `firing` | |
| `FLAPPINGEND` | `resolved` | |
| `DOWNTIMESTART` | `resolved` | Prevents planned maintenance holding an alert open |
| `DOWNTIMEEND` | `firing` | |
| `DOWNTIMEREMOVED` | `firing` | |

## Icinga Director

`contrib/director-basket/` generates an importable basket for sites managing
Icinga through Director:

```sh
make basket
```

Import via **Director → Configuration Baskets → Upload**. The basket creates
Icinga objects only; the package must still be installed on each master.

Exercised against Director 1.10. If your Director version rejects the basket,
open an issue.

## Development

```sh
make test     # run the test suite across sh, dash and bash
make lint     # shellcheck
make deb      # build .deb (requires fpm)
make rpm      # build .rpm (requires fpm)
```

Tests run the handler in `--dry-run` and assert on the resulting payload. No
network access or incident.io account required.

## Uninstallation

```sh
sudo make uninstall          # or apt remove / rpm -e
sudo rm /etc/icinga2/conf.d/incident-io-secrets.conf
sudo icinga2 daemon -C && sudo systemctl reload icinga2
```

## Support

Issues and feature requests:
[github.com/incident-io/icinga2/issues](https://github.com/incident-io/icinga2/issues).

Account support: support@incident.io.

## Licence

MIT. See [LICENSE](LICENSE).
