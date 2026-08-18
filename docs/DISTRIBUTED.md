# Distributed and HA setups

Notes for master/satellite estates. If you run a single master, none of this
applies to you.

## Only the masters need this

In Icinga's distributed model satellites and agents execute checks, but results
flow up and **notifications only ever fire from the master zone**.

So:

- Install the package on **every master in the master zone**. Nothing on
  satellites, nothing on agents.
- Only the masters need egress to `api.incident.io` on port 443. Satellites in
  remote datacenters do not — usually the thing your network team wants to know.

## The trap: zone sync does not move the handler

Icinga's config sync distributes `.conf` files to the nodes in a zone. It does
not distribute anything else. The handler at `/usr/bin/incident-io-icinga` is a
binary as far as Icinga is concerned, so it will not be synced.

Install the package on each master via your config management. The failure mode
if you forget is nasty and delayed: everything works until the day the other
master takes over notifications, and then alerts silently stop.

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
`check_source`, and it is the natural field to route on when satellites map to
datacenters:

```
check_source = satellite-fra-1  ->  EU on-call
check_source = satellite-nyc-1  ->  US on-call
```

## Keep the token out of zones.d

Put credentials in `/etc/icinga2/conf.d/incident-io-secrets.conf` on each
master, not in `zones.d`.

Config sync is TLS-encrypted, but it also writes synced files to
`/var/lib/icinga2/api/zones/` on every node in the zone. Keeping the token in
`conf.d` means it never enters the sync path at all.

## Satellite-only estates

If you have satellites that run their own notification component — an unusual
setup, but it exists where datacenters must alert independently of the masters —
install the package there too and put the `.conf` files in that satellite's zone
directory. Everything else works the same.
