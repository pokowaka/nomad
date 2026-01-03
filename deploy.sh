#!/bin/bash
#
# Project Nomad: The Injector
# Deploys source files from this repository to a running Nomad router.
# Usage: ./deploy.sh [ROUTER_IP_ADDRESS]

# --- Configuration & Safety ---
# Exit immediately if a command exits with a non-zero status.
set -e

# Use the IP address from the first argument, or default to 192.168.8.1
ROUTER_IP="${1:-192.168.8.1}"
ROUTER_USER="root"
ROUTER_DEST="${ROUTER_USER}@${ROUTER_IP}"

# --- Main Execution ---
echo "--- Starting deployment to Nomad router at ${ROUTER_IP} ---"

# 1. Sanity Check: Ensure the router is online before starting.
echo "[1/3] Pinging router..."
if ! ping -c 1 -W 2 "${ROUTER_IP}" > /dev/null; then
    echo "Error: Router at ${ROUTER_IP} is unreachable. Aborting." >&2
    exit 1
fi
echo "Router is online."

# 2. Payload Transfer: Recursively copy all files from 'src' to the router's root.
echo "[2/3] Copying project files via scp..."
scp -r src/* "${ROUTER_DEST}:/"

# 3. Provisioning & Restart: Execute remote commands via ssh.
echo "[3/3] Running provisioning and restarting services on router..."
ssh "${ROUTER_DEST}" '
    set -e
    echo "  - Remotely executing provisioning script..."
    # Manually run the uci-defaults script. It will self-delete after success.
    if [ -f /etc/uci-defaults/99-nomad-provision ]; then
        sh /etc/uci-defaults/99-nomad-provision
    else
        echo "  - Provisioning script not found, assuming already run."
    fi

    echo "  - Restarting services as requested..."
    # Per request, restart the nomad-monitor service.
    # Note: This init script is not yet defined in the project.
    # /etc/init.d/nomad-monitor restart
    # A full network restart is a common alternative to apply all changes:
    /etc/init.d/network restart
'

echo "--- Deployment to ${ROUTER_IP} complete! ---"
