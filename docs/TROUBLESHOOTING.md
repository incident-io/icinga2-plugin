# Troubleshooting

## Nothing arrives in incident.io

Work down the chain in order.

**1. Is Icinga firing the notification at all?**

```
grep -i 'notification' /var/log/icinga2/icinga2.log | tail -20
```

If you see nothing, Icinga has decided not to notify. Common causes: the object
is not opted in (`vars.incident_io = true`), it is in a downtime, the problem is
still in a SOFT state, or the notification is outside its `period`.

Confirm the notification object exists for the object you expect:

```
icinga2 object list --type Notification --name 'incident-io*' | head -40
```

**2. Is the handler running and failing?**

It logs to syslog under the tag `incident-io-icinga`:

```
journalctl -t incident-io-icinga -n 50
# or
grep incident-io-icinga /var/log/syslog | tail -50
```

**3. Exit codes**

| Code | Meaning |
| --- | --- |
| 0 | Delivered |
| 1 | Delivery failed — network, timeout or a 5xx from incident.io |
| 2 | Configuration error — missing env, bad argument, or a 401/403 |

**4. Test the path by hand, as the icinga user**

```
sudo -u nagios env \
  INCIDENT_IO_URL="$(...)" INCIDENT_IO_TOKEN="$(...)" \
  HOST_NAME=test-host STATE=CRITICAL NOTIFICATION_TYPE=PROBLEM \
  OUTPUT='manual test' \
  /usr/bin/incident-io-icinga
```

(The Icinga user is `nagios` on RHEL-family, `nagios` or `icinga` on Debian —
check `systemctl show icinga2 -p User`.)

## `could not reach ... check egress from this master`

Exit 1 with HTTP `000`: the master could not reach `api.incident.io`. Check
outbound firewall rules and proxy configuration.

If you use an outbound proxy, curl honours the standard variables — add them to
the command's `env` block in `incident-io-command.conf`:

```
env = {
  https_proxy = "http://proxy.example.com:3128"
  ...
}
```

## HTTP 401 or 403

The token does not match the alert source. The URL contains the alert source ID
and the token is scoped to it, so a URL and token taken from different sources
will fail this way. Re-copy both from the same source in incident.io.

## Alerts fire but never resolve

Something is making the dedup key differ between the PROBLEM and the RECOVERY.
Compare the two:

```
journalctl -t incident-io-icinga | grep 'delivered'
```

You should see the identical `icinga/<host>/<service>` string for both. If you
have customised the handler, check nothing state-dependent crept into the key.

Also confirm your apply rules include the recovery states and types — `OK` in
`states`, `Recovery` in `types`. Both are present by default.

## Duplicate alerts

Two Icinga instances pointed at one alert source will collide if they monitor
objects with the same names. Give each one a distinguishing default:

```
globals.IncidentIoDefaultMetadata = { icinga_instance = "primary" }
```

...and if the names genuinely overlap, customise the dedup key in the handler to
include it.

## Metadata is missing from alerts

Check the function output directly:

```
icinga2 console --connect 'https://myuser:mypass@localhost:5665/'
<1> => incident_io_metadata(get_host("web-01"), null)
```

`--connect` is required: a bare `icinga2 console` does not load your
configuration, so the function is undefined there and you get `Argument is not a
callable object` rather than an answer. It needs the `api` feature enabled and
an `ApiUser` with the `console` permission.

If that looks right but alerts lack the fields, look for a warning in syslog —
the handler drops malformed or oversized metadata (over 32 KB) rather than
failing the alert. See [METADATA.md](METADATA.md).

## Config validation fails after install

```
icinga2 daemon -C
```

If it complains about `IncidentIoUrl` being undefined, you have installed the
`.conf` files but not created `incident-io-secrets.conf` from the example.
