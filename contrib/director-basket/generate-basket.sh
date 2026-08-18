#!/bin/sh
#
# Emit an Icinga Director "configuration basket" for the incident.io
# integration, so Director users can import the command, contact and
# notification template through the web UI instead of editing files.
#
#   ./contrib/director-basket/generate-basket.sh > director-basket.json
#
# Import with:  Director -> Configuration Baskets -> Upload
#           or: icingacli director basket restore < director-basket.json
#
# STATUS: contrib, community-supported. The file layout follows Director's
# basket schema but has been exercised against Director 1.10 only. Please open
# an issue if your Director version rejects it.
#
# NOTE: Director cannot install the handler binary. Install the package on
# every master first - this basket only creates the Icinga objects.

set -eu

cat <<'JSON'
{
  "Command": {
    "incident-io": {
      "command": "/usr/bin/incident-io-icinga",
      "methods_execute": "PluginNotification",
      "object_name": "incident-io",
      "object_type": "object",
      "vars": {
        "incident_io_url": "${incident_io_url}",
        "incident_io_token": "${incident_io_token}",
        "incident_io_icingaweb_url": "${incident_io_icingaweb_url}"
      }
    }
  },
  "NotificationTemplate": {
    "incident-io-notification": {
      "command": "incident-io",
      "notification_interval": 3600,
      "object_name": "incident-io-notification",
      "object_type": "template",
      "states": [ "Warning", "Critical", "Unknown", "OK" ],
      "types": [
        "Problem", "Recovery", "Acknowledgement", "Custom",
        "FlappingStart", "FlappingEnd",
        "DowntimeStart", "DowntimeEnd", "DowntimeRemoved"
      ],
      "users": [ "incident-io" ]
    }
  },
  "User": {
    "incident-io": {
      "display_name": "incident.io",
      "enable_notifications": true,
      "object_name": "incident-io",
      "object_type": "object",
      "period": "24x7"
    }
  },
  "DataList": {
    "incident.io alert routing": {
      "list_name": "incident.io alert routing",
      "owner": "icinga2-incident-io",
      "entries": [
        { "entry_name": "true",  "entry_value": "Send to incident.io" },
        { "entry_name": "false", "entry_value": "Do not send to incident.io" }
      ]
    }
  },
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
