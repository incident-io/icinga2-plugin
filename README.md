# incident.io for Icinga 2

Forward Icinga 2 notifications to [incident.io](https://incident.io) as alerts.

Icinga keeps doing what it is good at — scheduling checks, tracking state,
handling downtimes and flapping. incident.io takes it from there: routing,
escalation, on-call schedules and incident response.

## What it does

- Sends host and service notifications to an incident.io HTTP alert source.
- Resolves alerts automatically on recovery, so nothing lingers.
- Respects downtimes, acknowledgements and notification periods — Icinga's
  suppression rules apply before anything is sent.
- Attaches whatever context you want to each alert, so incident.io can route on
  team, datacenter, tier, or any custom variable you already have. See
  [docs/METADATA.md](docs/METADATA.md).
- Links each alert back to the object in Icinga Web 2.
- Works with distributed master/satellite setups, including HA master pairs,
  without duplicate alerts. See [docs/DISTRIBUTED.md](docs/DISTRIBUTED.md).

## Requirements

- Icinga 2, version 2.11 or newer
- `curl` on each master
- Outbound HTTPS from each master to `api.incident.io`

The handler is POSIX shell. It deliberately does not require `jq`, Perl or
Python, because Icinga masters in locked-down estates frequently have none of
them.

## Install

Install on **every master in your master zone**. Nothing is needed on
satellites or agents — notifications only ever fire from the master zone.

### From a package

Download the latest `.deb` or `.rpm` from
[Releases](https://github.com/incident-io/icinga2/releases):

```sh
# Debian / Ubuntu
sudo apt install ./icinga2-incident-io_1.0.0_all.deb

# RHEL / Rocky / SLES
sudo rpm -i icinga2-incident-io-1.0.0-1.noarch.rpm
```

### From source

```sh
git clone https://github.com/incident-io/icinga2.git
cd icinga2
sudo make install
```

Either way you get:

```
/usr/bin/incident-io-icinga                                  the handler
/etc/icinga2/zones.d/master/incident-io-command.conf         command + metadata builder
/etc/icinga2/zones.d/master/incident-io-notifications.conf   apply rules
/etc/icinga2/conf.d/incident-io-secrets.conf.example         credentials template
```

## Configure

### 1. Create an alert source in incident.io

**Settings → Alerts → Sources → New source → HTTP.** Copy the URL and the
bearer token it shows you.

### 2. Add your credentials

On each master:

```sh
sudo cp /etc/icinga2/conf.d/incident-io-secrets.conf.example \
        /etc/icinga2/conf.d/incident-io-secrets.conf
sudo chown root:icinga /etc/icinga2/conf.d/incident-io-secrets.conf
sudo chmod 0640        /etc/icinga2/conf.d/incident-io-secrets.conf
sudoedit /etc/icinga2/conf.d/incident-io-secrets.conf
```

```
const IncidentIoUrl   = "https://api.incident.io/v2/alert_events/http/YOUR_SOURCE_ID"
const IncidentIoToken = "YOUR_TOKEN"
const IncidentIoIcingaWebUrl = "https://icinga.example.com/icingaweb2"
```

This lives in `conf.d`, not `zones.d`, on purpose — it keeps the token off the
config-sync path. See [docs/DISTRIBUTED.md](docs/DISTRIBUTED.md).

### 3. Opt objects in

Alerting is opt-in, so installing this changes nothing until you say so:

```
object Host "web-01.dc-fra" {
  import "generic-host"
  address = "10.0.1.4"

  vars.incident_io = true      // this host and all its services
}
```

Opt out an individual noisy service:

```
apply Service "backup-log" {
  check_command = "backup_log"
  vars.incident_io = false
  assign where host.vars.incident_io
}
```

To route everything instead, change the `assign where` lines in
`incident-io-notifications.conf` to `assign where true`.

### 4. Reload

```sh
sudo icinga2 daemon -C && sudo systemctl reload icinga2
```

## Verify

Build a payload without sending it:

```sh
INCIDENT_IO_URL=x INCIDENT_IO_TOKEN=x \
HOST_NAME=web-01 SERVICE_NAME='disk /' STATE=CRITICAL \
NOTIFICATION_TYPE=PROBLEM OUTPUT='DISK CRITICAL - 12% free' \
  incident-io-icinga --dry-run
```

Then send a real one from Icinga Web 2: open any host you have opted in and
choose **Send custom notification**. It should appear in incident.io within a
few seconds.

## What an alert looks like

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
    "source": "icinga",
    "team": "payments",
    "datacenter": "fra"
  }
}
```

`team` and `datacenter` there are custom — anything you can express in Icinga
config can become metadata, and incident.io can route on all of it.
[docs/METADATA.md](docs/METADATA.md) covers the four ways to add it.

The `deduplication_key` is what makes recoveries work: the RECOVERY notification
resolves the same alert the PROBLEM opened, and re-notifications update it
rather than creating duplicates.

## How notification types map

| Icinga | incident.io |
| --- | --- |
| `PROBLEM` | `firing` |
| `RECOVERY` | `resolved` |
| `ACKNOWLEDGEMENT` | `firing`, with the acknowledging user and comment in the description |
| `FLAPPINGSTART` | `firing` |
| `FLAPPINGEND` | `resolved` |
| `DOWNTIMESTART` | `resolved` — planned maintenance shouldn't hold an alert open |
| `DOWNTIMEEND` / `DOWNTIMEREMOVED` | `firing` |
| `CUSTOM` | `firing` |

## Icinga Director

If you manage Icinga with Director, `contrib/director-basket/` generates an
importable basket so you can create the objects through the web UI instead of
editing files:

```sh
make basket
# then: Director -> Configuration Baskets -> Upload
```

You still need the package installed on each master — Director manages Icinga
objects, not files on disk.

## Development

```sh
make test     # run the suite against sh, dash and bash
make lint     # shellcheck
make deb      # build a .deb (needs fpm)
make rpm      # build an .rpm (needs fpm)
make packages # build both in Docker, no local toolchain needed
```

Tests run the handler in `--dry-run` mode and assert on the payload, so they
need no network and no incident.io account.

## Uninstall

```sh
sudo make uninstall        # or apt remove / rpm -e
sudo rm /etc/icinga2/conf.d/incident-io-secrets.conf
sudo icinga2 daemon -C && sudo systemctl reload icinga2
```

## Support

Bugs and feature requests: [open an issue](https://github.com/incident-io/icinga2/issues).

For help with your incident.io account, contact support@incident.io.

## License

MIT — see [LICENSE](LICENSE).
