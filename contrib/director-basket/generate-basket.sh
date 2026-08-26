#!/bin/sh
#
# Emit an Icinga Director "configuration basket" carrying the two custom
# variable fields this integration reads, so that hosts and services managed in
# Director can be opted in from the web UI instead of by editing files.
#
#   ./contrib/director-basket/generate-basket.sh > director-basket.json
#
# Import with:  Director -> Configuration Baskets -> Upload
#           or: icingacli director basket restore < director-basket.json
#
# Deliberately just the data fields.
#
# The NotificationCommand, the User, the notification template and the apply
# rules all come from the package, in /etc/icinga2/conf.d/, and a Director site
# gets them the same way everyone else does. Director cannot own the command
# regardless: the integration passes its configuration through the command's
# env block, and setting env from Director has been an open feature request
# since 2016 (Icinga/icingaweb2-module-director#256). An earlier version of this
# basket shipped its own copies of those four objects, which duplicated working
# configuration with versions that could not work.
#
# So the only thing Director is genuinely needed for is setting
# vars.incident_io on the host and service objects it owns, which is what these
# fields are for. After importing, add them to the host and service templates
# you want to be able to opt in.
#
# NOT VERIFIED: whether an apply rule in conf.d reliably matches hosts that
# Director writes into zones.d. Notifications fire from the master zone so it
# should, but Director builds its own config stage and there are reported cases
# of zone handling going wrong when an apply rule and its target are split
# across the two. Confirm on your own Director with:
#
#   icinga2 object list --type Notification --name 'incident-io*'
#
# after ticking the box on one host. Please open an issue either way.

set -eu

cat <<'JSON'
{
  "Datafield": {
    "1": {
      "varname": "incident_io",
      "caption": "Send alerts to incident.io",
      "description": "Route this object's notifications to incident.io",
      "datatype": "Icinga\\Module\\Director\\DataType\\DataTypeBoolean"
    },
    "2": {
      "varname": "incident_io_metadata",
      "caption": "incident.io metadata",
      "description": "Extra key/value pairs attached to every alert for this object",
      "datatype": "Icinga\\Module\\Director\\DataType\\DataTypeDictionary"
    }
  }
}
JSON
