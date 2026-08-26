---
name: Bug report
about: Something in the integration does not behave as documented
labels: bug
---

**What happened, and what did you expect instead?**

**Versions**

- Icinga 2 (`icinga2 --version`):
- Handler (`incident-io-icinga --version`):
- Platform:

**The payload the handler built**

Run the handler with `--dry-run`, which sends nothing, and paste the output.
Check it for anything you would rather not post publicly first, and never
include your alert source token.

```
INCIDENT_IO_URL=x INCIDENT_IO_TOKEN=x \
HOST_NAME=web-01 SERVICE_NAME='disk /' STATE=CRITICAL \
NOTIFICATION_TYPE=PROBLEM OUTPUT='DISK CRITICAL - 12% free' \
  incident-io-icinga --dry-run
```

**Anything in syslog?**

```
journalctl -t incident-io-icinga -n 50
```
