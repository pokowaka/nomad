#!/bin/bash
#
# Project Nomad: The Unified Injector
# Deploys source files and provisions network configuration including secrets.
# Usage: ./deploy.sh [ROUTER_IP_ADDRESS]

# --- Configuration & Safety ---
set -e
BASE_DIR=$(dirname "$0")

# 1. Load Secrets
if ! source "${BASE_DIR}/secrets/nomad.env"; then
    echo "Error: secrets/nomad.env not found or failed to source." >&2
    echo "Please create it from the example." >&2
    exit 1
fi

# --- Variables ---
ROUTER_IP="${1:-192.168.10.1}"
ROUTER_USER="root"
ROUTER_DEST="${ROUTER_USER}@${ROUTER_IP}"
PACKAGES="openssh-sftp-server travelmate wireguard-tools nftables kmod-nft-core libubox uhttpd ip-full conntrack https-dns-proxy"

# --- Functions ---
# Generates a shell script with UCI commands to configure the router's network.
generate_network_script() {
    # Extract host and port from endpoint strings
    WG0_ENDPOINT_HOST=${WG0_ENDPOINT%:*}
    WG0_ENDPOINT_PORT=${WG0_ENDPOINT#*:}
    WG1_ENDPOINT_HOST=${WG1_ENDPOINT%:*}
    WG1_ENDPOINT_PORT=${WG1_ENDPOINT#*:}

    # Use a heredoc to create the script content
    cat << EOF
#!/bin/sh
set -e
echo "--- Starting remote network provisioning ---"

# --- Clean previous config for idempotency ---
uci -q delete network.wg0
uci -q delete network.wg1
# Old peer sections might have different names, this is a best effort
uci -q delete network.\$(uci show network | grep 'wireguard_wg0' | cut -d. -f2)
uci -q delete network.\$(uci show network | grep 'wireguard_wg1' | cut -d. -f2)

# --- Configure wg0 (Work) ---
echo "  - Configuring wg0 interface..."
uci set network.wg0='interface'
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key='${WG0_PRIVATE_KEY}'
uci add_list network.wg0.addresses='${WG0_ADDRESS}'
uci set network.wg0.mtu='1420'

uci set network.wg_peer_work='wireguard_wg0'
uci set network.wg_peer_work.public_key='${WG0_PUBLIC_KEY}'
uci set network.wg_peer_work.endpoint_host='${WG0_ENDPOINT_HOST}'
uci set network.wg_peer_work.endpoint_port='${WG0_ENDPOINT_PORT}'
uci set network.wg_peer_work.persistent_keepalive='25'
uci add_list network.wg_peer_work.allowed_ips='${WG0_ALLOWED_IPS}'

# --- Configure wg1 (Home) ---
echo "  - Configuring wg1 interface..."
uci set network.wg1='interface'
uci set network.wg1.proto='wireguard'
uci set network.wg1.private_key='${WG1_PRIVATE_KEY}'
uci add_list network.wg1.addresses='${WG1_ADDRESS}'
uci set network.wg1.mtu='1420'

uci set network.wg_peer_home='wireguard_wg1'
uci set network.wg_peer_home.public_key='${WG1_PUBLIC_KEY}'
uci set network.wg_peer_home.endpoint_host='${WG1_ENDPOINT_HOST}'
uci set network.wg_peer_home.endpoint_port='${WG1_ENDPOINT_PORT}'
uci set network.wg_peer_home.persistent_keepalive='25'
uci add_list network.wg_peer_home.allowed_ips='${WG1_ALLOWED_IPS}'

# --- Firewall: Add WG interfaces to WAN zone for masquerading ---
# This assumes the WAN zone is the second zone (index 1), default in OpenWrt.
echo "  - Assigning firewall zones..."
uci add_list firewall.@zone[1].network='wg0'
uci add_list firewall.@zone[1].network='wg1'

# --- Commit all changes ---
echo "  - Committing network and firewall changes..."
uci commit network
uci commit firewall

echo "--- Remote network provisioning complete ---"
EOF
}

# --- Main Execution ---
echo "--- Starting Unified Deployment to ${ROUTER_IP} ---"

# Step 1: Sanity Check
echo "[1/5] Pinging router..."
if ! ping -c 1 -W 2 "${ROUTER_IP}" > /dev/null; then
    echo "Error: Router at ${ROUTER_IP} is unreachable." >&2; exit 1
fi
echo "Router is online."

# Step 2: Install Dependencies
echo "[2/5] Installing dependencies via opkg..."
ssh "${ROUTER_DEST}" "opkg update && opkg install ${PACKAGES}"

# Step 3: Payload Transfer
echo "[3/5] Copying project files via scp..."
scp -q -r "${BASE_DIR}/src/"* "${ROUTER_DEST}:/"

# Step 4: Network Provisioning
echo "[4/5] Generating and executing remote network configuration..."
generate_network_script | ssh "${ROUTER_DEST}" "/bin/sh"

# Step 5: Finalize
echo "[5/5] Running final provisioning and restarting network..."
ssh "${ROUTER_DEST}" '
    set -e
    if [ -f /etc/uci-defaults/99-nomad-provision ]; then
        echo "  - Running uci-defaults provisioner..."
        sh /etc/uci-defaults/99-nomad-provision
    fi
    echo "  - Restarting network service..."
    /etc/init.d/network restart
'

echo "--- Unified Deployment to ${ROUTER_IP} complete! ---"