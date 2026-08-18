# Metadata

Every alert this integration sends carries a `metadata` object. incident.io can
route, group and filter on anything in it, so the more of your Icinga context
you put here, the better your alert routing gets.

You are not limited to a fixed set of fields. Anything you can express in
Icinga's config language can become metadata.

## What you get for free

Without configuring anything:

| Key | Example | Where it comes from |
| --- | --- | --- |
| `host` | `web-01.dc-fra` | `$host.name$` |
| `service` | `disk /` | `$service.name$`, empty for host alerts |
| `state` | `CRITICAL` | current state |
| `notification_type` | `PROBLEM` | Icinga notification type |
| `check_source` | `satellite-fra-1` | the node that actually ran the check |
| `hostgroups` | `["linux", "prod"]` | `host.groups` |
| `servicegroups` | `["disk"]` | `service.groups`, service alerts only |
| `source` | `icinga` | constant |

`check_source` is the one people overlook. In a distributed setup it names the
satellite that executed the check, which usually maps to a datacenter or
region — it is the single most useful field for routing.

## Adding your own

### Option 1: promote custom variables you already have

If your hosts already carry custom vars, list the ones worth alerting on:

```
object Host "web-01.dc-fra" {
  vars.incident_io = true

  vars.datacenter  = "fra"
  vars.team        = "payments"
  vars.tier        = 1
  vars.runbook     = "https://wiki.example.com/runbooks/web"

  vars.incident_io_metadata_vars = [ "datacenter", "team", "tier", "runbook" ]
}
```

Produces:

```json
"metadata": {
  "host": "web-01.dc-fra", "service": "disk /", "state": "CRITICAL",
  "notification_type": "PROBLEM", "check_source": "satellite-fra-1",
  "hostgroups": ["linux", "prod"], "source": "icinga",
  "datacenter": "fra", "team": "payments", "tier": 1,
  "runbook": "https://wiki.example.com/runbooks/web"
}
```

This is an allowlist on purpose. Check commands often keep credentials in custom
vars (`vars.mysql_password` and friends), so nothing is exported unless you name
it.

### Option 2: an explicit dictionary

For values that don't already exist as custom vars:

```
object Host "web-01.dc-fra" {
  vars.incident_io = true

  vars.incident_io_metadata = {
    team        = "payments"
    escalation  = "follow-the-sun"
    slack       = "#payments-alerts"
    business_hours_only = false
  }
}
```

Types are preserved: strings stay strings, numbers stay numbers, `true` and
`false` stay booleans. Nested dictionaries and arrays work too:

```
vars.incident_io_metadata = {
  owner = {
    squad   = "core-infra"
    slack   = "#core-infra"
    manager = "rloffelmacher"
  }
  compliance = [ "pci", "sox" ]
}
```

### Option 3: estate-wide defaults

In `incident-io-secrets.conf`, applied to every alert:

```
globals.IncidentIoDefaultMetadata = {
  icinga_instance = "primary"
  environment     = "production"
  region          = "eu-central"
}
```

Useful when several Icinga installations feed one incident.io account.

### Option 4: service-level, via apply rules

Anywhere you can write Icinga config, you can set metadata — including inside
apply rules, so it scales across thousands of services:

```
apply Service "disk" {
  check_command = "disk"

  vars.incident_io = true
  vars.incident_io_metadata = {
    category = "capacity"
    severity_hint = "low"
  }

  assign where host.vars.os == "Linux"
}
```

## Precedence

Later layers overwrite earlier ones on key collision:

1. built-in fields (`host`, `service`, `state`, …)
2. `globals.IncidentIoDefaultMetadata`
3. host `vars.incident_io_metadata_vars`
4. host `vars.incident_io_metadata`
5. service `vars.incident_io_metadata_vars`
6. service `vars.incident_io_metadata`

So a service can override a host default, and either can override a built-in —
handy if you want `source` to read `icinga-eu` rather than `icinga`.

## How this works

Worth understanding, because it explains the one real constraint.

`incident-io-command.conf` defines a function, `incident_io_metadata()`, which
assembles a dictionary and hands it to Icinga's built-in
[`Json.encode()`](https://icinga.com/docs/icinga-2/latest/doc/18-library-reference/).
The result is passed to the handler as one environment variable,
`INCIDENT_IO_METADATA_JSON`.

Because Icinga has already produced valid JSON, the handler splices it into the
payload verbatim rather than parsing it. That is what makes arbitrary nesting
possible in a script with no JSON library — the JSON was built by Icinga, not by
the shell.

The constraint that falls out: the handler validates only the *shape* (it must
be a JSON object, under 32 KB). If it isn't, the handler logs a warning and
sends the alert without your extra metadata rather than dropping the alert. An
alert with thin metadata beats no alert.

## Checking your work

`icinga2 console` evaluates the function against real objects without sending
anything:

```
$ icinga2 console
<1> => var h = get_host("web-01.dc-fra")
<2> => incident_io_metadata(h, null)
"{\"hostgroups\":[\"linux\",\"prod\"],\"datacenter\":\"fra\",\"team\":\"payments\"}"
```

To see a whole payload, run the handler by hand:

```
INCIDENT_IO_URL=x INCIDENT_IO_TOKEN=x \
HOST_NAME=web-01 SERVICE_NAME='disk /' STATE=CRITICAL \
NOTIFICATION_TYPE=PROBLEM OUTPUT='DISK CRITICAL' \
INCIDENT_IO_METADATA_JSON='{"team":"payments"}' \
  /usr/bin/incident-io-icinga --dry-run
```

`--dry-run` prints the payload and sends nothing.
