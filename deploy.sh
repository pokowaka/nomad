#!/bin/bash
#
# Project Nomad: The Unified Injector v10 (Push-based Deployment)
# Deploys files and provisions the router by copying a configuration script
# and executing it remotely with secrets as environment variables.
# Usage: ./deploy.sh [ROUTER_IP_ADDRESS]

# --- Configuration & Safety ---
# set -e
set -x
BASE_DIR=$(dirname "$0")

# 1. Load Secrets
if ! source "${BASE_DIR}/secrets/nomad.env"; then
    echo "Error: secrets/nomad.env not found. Please create it from the example." >&2
    exit 1
fi

# --- Variables ---
ROUTER_IP="${1:-192.168.10.1}"
ROUTER_USER="root"
ROUTER_DEST="${ROUTER_USER}@${ROUTER_IP}"
REMOTE_SCRIPT_PATH="/tmp/configure_remote.sh"
PACKAGES="openssh-sftp-server travelmate wireguard-tools nftables kmod-nft-core libubox uhttpd ip-full conntrack https-dns-proxy"

# --- Main Execution ---
echo "--- Starting Unified Deployment v10 to ${ROUTER_IP} ---"

# Step 1: Pinging router
echo "[1/4] Pinging router..."
if ! ping -c 1 -W 2 "${ROUTER_IP}" > /dev/null; then echo "Error: Router at ${ROUTER_IP} is unreachable." >&2; exit 1; fi
echo "Router is online."

# Step 2: Install Dependencies & Copy Files
echo "[2/5] Installing dependencies and copying files..."
ssh "${ROUTER_DEST}" "opkg update && opkg install ${PACKAGES}"
scp -q -r "${BASE_DIR}/src/"* "${ROUTER_DEST}:/"
scp -q "${BASE_DIR}/config_router.sh" "${ROUTER_DEST}:${REMOTE_SCRIPT_PATH}"

# Step 3: Set Permissions & Define Routing Tables
echo "[3/5] Setting permissions and defining routing tables..."
ssh "${ROUTER_DEST}" '
    set -e
    # Make scripts executable
    chmod +x /usr/bin/nomad-monitor
    chmod +x /usr/bin/nomad-steer
    chmod +x /usr/bin/config.sh
    chmod +x /etc/init.d/10-nomad-safemode
    chmod +x /etc/hotplug.d/iface/99-nomad-controller
    chmod +x /etc/travelmate/user_hooks.sh
    chmod +x /www/nomad/api/steering.cgi

    # Ensure custom routing tables are defined
    grep -qxF "100 nomad_work" /etc/iproute2/rt_tables || echo "100 nomad_work" >> /etc/iproute2/rt_tables
    grep -qxF "101 nomad_home" /etc/iproute2/rt_tables || echo "101 nomad_home" >> /etc/iproute2/rt_tables
    grep -qxF "102 nomad_wan" /etc/iproute2/rt_tables || echo "102 nomad_wan" >> /etc/iproute2/rt_tables
'

# Step 4: Execute Remote Configuration
echo "[4/5] Executing remote configuration script with secrets..."
REMOTE_COMMAND=" \
    export WG0_PRIVATE_KEY='${WG0_PRIVATE_KEY}'; \
    export WG0_PUBLIC_KEY='${WG0_PUBLIC_KEY}'; \
    export WG0_ENDPOINT_HOST='${WG0_ENDPOINT%:*}'; \
    export WG0_ENDPOINT_PORT='${WG0_ENDPOINT#*:}'; \
    export WG0_ADDRESS='${WG0_ADDRESS}'; \
    export WG0_ALLOWED_IPS='${WG0_ALLOWED_IPS}'; \
    export WG1_PRIVATE_KEY='${WG1_PRIVATE_KEY}'; \
    export WG1_PUBLIC_KEY='${WG1_PUBLIC_KEY}'; \
    export WG1_ENDPOINT_HOST='${WG1_ENDPOINT%:*}'; \
    export WG1_ENDPOINT_PORT='${WG1_ENDPOINT#*:}'; \
    export WG1_ADDRESS='${WG1_ADDRESS}'; \
    export WG1_ALLOWED_IPS='${WG1_ALLOWED_IPS}'; \
    /bin/sh ${REMOTE_SCRIPT_PATH}"
ssh "${ROUTER_DEST}" "${REMOTE_COMMAND}"

# Step 5: Finalize
echo "[5/5] Running final setup and restarting services..."
ssh "${ROUTER_DEST}" '
    set -e
    echo "  - Running final provisioning script (if present)..."
    if [ -f /etc/uci-defaults/99-nomad-provision ]; then sh /etc/uci-defaults/99-nomad-provision; fi
    echo "  - Enabling safemode service..."
    /etc/init.d/10-nomad-safemode enable
    echo "  - Restarting core services..."
    /etc/init.d/network restart
    /etc/init.d/firewall restart
    echo "  - Triggering monitor to apply initial state..."
    nohup /usr/bin/nomad-monitor >/dev/null 2>&1 &
'

echo "--- Unified Deployment to ${ROUTER_IP} complete! ---"