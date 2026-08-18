# Distributed and HA setups

Notes for master/satellite estates. If you run a single master, none of this
applies to you.

## Only the masters need this

In Icinga's distributed model satellites and agents execute checks, but results
flow up and **notifications only ever fire from the master zone**.

So:

- Install the package on **every master in the master zone**. Nothing on
  satellites, nothing on agents.
- Only the masters need egress to `api.incident.io` on port 443. Satellites do
  not.

## Zone sync does not distribute the handler

Icinga's config sync distributes `.conf` files to the nodes in a zone. It does
not distribute anything else. The handler at `/usr/bin/incident-io-icinga` is a
binary as far as Icinga is concerned, so it will not be synced.

Install the package on each master via your config management. If one master is
missed, notifications succeed until that master takes over, then fail silently
from Icinga's perspective — the failure surfaces only in syslog.

Check both masters:

```
salt -G 'role:icinga-master' cmd.run 'incident-io-icinga --version'
# or
ansible icinga_masters -a 'incident-io-icinga --version'
```

## You will not get duplicate alerts

Icinga's notification component runs with `enable_ha = true` by default. In a
two-master zone exactly one master owns notifications at any moment, and
failover is automatic. You get one alert, not two.

Should that assumption ever break, the deduplication key is derived only from
host and service names — never from a timestamp or the sending node — so two
masters sending the same notification would still collapse to a single alert in
incident.io.

## `check_source` tells you where the check ran

`$service.check_source$` names the endpoint that actually executed the check,
which in a distributed setup is the satellite. It lands in metadata as
`check_source`. Where satellites map to datacenters, route on it:

```
check_source = satellite-fra-1  ->  EU on-call
check_source = satellite-nyc-1  ->  US on-call
```

## Why everything lives in conf.d, not zones.d

The obvious layout would put the command and apply rules in
`/etc/icinga2/zones.d/master/` and let config sync distribute them. This
integration does not, for two reasons.

**Constants do not cross the boundary.** Configuration synced from `zones.d`
cannot see constants defined in `conf.d` or `constants.conf`. A
`NotificationCommand` in `zones.d` referencing `IncidentIoUrl` therefore fails
validation. The alternative is putting the credentials in `zones.d` too, which
writes the token to `/var/lib/icinga2/api/zones/` on every node in the zone.

**Zone sync buys nothing here.** It distributes `.conf` files but not
executables, so the handler has to be installed on every master anyway.
Once you are installing per-master, installing the config per-master too costs
nothing and removes the constants problem entirely.

The trade-off is drift: two masters could end up with different config. Manage
the file with the same tooling that installs the package and this does not
arise.

If you would rather use zone sync, put all four files - command,
notifications, secrets and the constants they reference - together in
`zones.d/master/`, and accept the token being staged under
`/var/lib/icinga2/api/zones/` on the masters.

## Satellites running their own notification component

Where satellites are configured to notify independently of the masters, install
the package on those satellites and place the `.conf` files in the relevant
zone directory. Behaviour is otherwise identical.
