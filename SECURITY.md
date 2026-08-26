# Security

## Reporting a vulnerability

Please report security issues to **support@incident.io**, marking the subject
line as a security report, rather than opening a public issue. Include the version (`incident-io-icinga --version`), what you
observed, and the steps to reproduce it. We will acknowledge your report and
keep you updated as we work on a fix.

Please do not test against other people's infrastructure.

## What this integration handles

The handler runs on your Icinga masters, as the user Icinga runs as. It reads
notification data from its environment, builds a JSON payload, and POSTs it to
your incident.io alert source over HTTPS. It opens no listening socket, writes no
state to disk beyond a temporary file for the HTTP response body, and makes no
outbound request other than to the URL you configure.

Two things are worth knowing when you deploy it.

**The alert source token is a credential.** It lives in
`/etc/icinga2/conf.d/incident-io-secrets.conf`. Install that file `0640`, owned
`root:icinga`, so that only root and Icinga can read it. Keep it out of
`zones.d`: config sync would stage a copy under `/var/lib/icinga2/api/zones/` on
every node in the zone. The token authorises creating alerts in your incident.io
account and nothing else, and you can roll it from the alert source page at any
time.

**Metadata is data you choose to export.** Custom variables can hold check
credentials, so nothing is sent unless you name it. `vars.incident_io_metadata`
is an explicit dictionary, and `vars.incident_io_metadata_vars` is an allowlist
of variable names. Neither dumps every custom variable on the object. Review
what you add: whatever you put in metadata leaves your estate and is visible to
anyone who can see the alert in incident.io.

## Supported versions

Security fixes land on the latest release. There are no maintained release
branches.
