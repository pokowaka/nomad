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

# List of required packages for the router.
PACKAGES="travelmate wireguard-tools nftables kmod-nft-core libubox uhttpd ip-full conntrack https-dns-proxy"

# --- Main Execution ---
echo "--- Starting deployment to Nomad router at ${ROUTER_IP} ---"

# 1. Sanity Check: Ensure the router is online before starting.
echo "[1/4] Pinging router..."
if ! ping -c 1 -W 2 "${ROUTER_IP}" > /dev/null; then
    echo "Error: Router at ${ROUTER_IP} is unreachable. Aborting." >&2
    exit 1
fi
echo "Router is online."

# 2. Install Dependencies
echo "[2/4] Installing dependencies on router via opkg..."
ssh "${ROUTER_DEST}" "opkg update && opkg install ${PACKAGES}"

# 3. Payload Transfer: Recursively copy all files from 'src' to the router's root.
echo "[3/4] Copying project files via scp..."
scp -r src/* "${ROUTER_DEST}:/"

# 4. Provisioning & Restart: Execute remote commands via ssh.
echo "[4/4] Running provisioning and restarting services on router..."
ssh "${ROUTER_DEST}" '
    set -e
    echo "  - Remotely executing provisioning script..."
    # Manually run the uci-defaults script. It will self-delete after success.
    if [ -f /etc/uci-defaults/99-nomad-provision ]; then
        sh /etc/uci-defaults/99-nomad-provision
    else
        echo "  - Provisioning script not found, assuming already run."
    fi

    echo "  - Restarting network to apply all changes..."
    # A full network restart is the most reliable way to apply all networking
    # and hotplug changes in OpenWrt.
    /etc/init.d/network restart
'

echo "--- Deployment to ${ROUTER_IP} complete! ---"
