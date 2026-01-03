#!/bin/sh

# Project Nomad: Travelmate Hooks
# /etc/travelmate/user_hooks.sh
#
# This script is sourced by travelmate and allows reacting to events.

# This function is called automatically by travelmate after a successful
# connection to an upstream station (e.g., after a captive portal login).
tmate_connected() {
    # We trigger the nomad-monitor in the background.
    # This re-evaluates the system state, bringing up VPNs and locking down
    # the firewall now that we have a real internet connection.
    logger -t "nomad-tmate-hook" "Connection established, triggering nomad-monitor."
    /usr/bin/nomad-monitor &
}

# Other potential hooks (unused for now):
# tmate_disconnected() { ... }
# tmate_wifidisabled() { ... }
