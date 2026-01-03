#!/bin/sh
set -x
set -e
echo "--- Starting Remote Configuration ---"

# 1. NETWORK CONFIGURATION
echo "  - Configuring Network Interfaces..."
uci -q delete network.wg0 || true; uci -q delete network.wg1 || true
# Clean up old peers
for peer in $(uci show network | grep 'wireguard_wg' | cut -d. -f2 | cut -d'=' -f1 | sort -u); do
    uci -q delete network.$peer || true
done

echo "  - Configuring WG0 (Work)..."
uci set network.wg0='interface'
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="$WG0_PRIVATE_KEY"
uci add_list network.wg0.addresses="$WG0_ADDRESS"
uci set network.wg0.mtu='1420'
uci set network.wg0.auto='0'
uci set network.wg_peer_work='wireguard_wg0'
uci set network.wg_peer_work.public_key="$WG0_PUBLIC_KEY"
uci set network.wg_peer_work.endpoint_host="$WG0_ENDPOINT_HOST"
uci set network.wg_peer_work.endpoint_port="$WG0_ENDPOINT_PORT"
uci set network.wg_peer_work.persistent_keepalive='25'
uci add_list network.wg_peer_work.allowed_ips="$WG0_ALLOWED_IPS"

echo "  - Configuring WG1 (Home)..."
uci set network.wg1='interface'
uci set network.wg1.proto='wireguard'
uci set network.wg1.private_key="$WG1_PRIVATE_KEY"
uci add_list network.wg1.addresses="$WG1_ADDRESS"
uci set network.wg1.mtu='1420'
uci set network.wg1.auto='0'
uci set network.wg_peer_home='wireguard_wg1'
uci set network.wg_peer_home.public_key="$WG1_PUBLIC_KEY"
uci set network.wg_peer_home.endpoint_host="$WG1_ENDPOINT_HOST"
uci set network.wg_peer_home.endpoint_port="$WG1_ENDPOINT_PORT"
uci set network.wg_peer_home.persistent_keepalive='25'
uci add_list network.wg_peer_home.allowed_ips="$WG1_ALLOWED_IPS"

# 2. FIREWALL CONFIGURATION
echo "  - Configuring Firewall..."

# --- Nomad rules file (defines the custom chain) ---
uci -q delete firewall.nomad_rules
uci set firewall.nomad_rules=include
uci set firewall.nomad_rules.path='/etc/nftables.d/nomad-filter.nft'
uci set firewall.nomad_rules.type='nftables'
uci set firewall.nomad_rules.family='inet'
uci set firewall.nomad_rules.reload='1'

# --- Nomad shim file (jumps from forward → nomad_forward) ---
uci -q delete firewall.nomad_shim
uci set firewall.nomad_shim=include
uci set firewall.nomad_shim.path='/etc/nftables.d/nomad-shim.nft'
uci set firewall.nomad_shim.type='nftables'
uci set firewall.nomad_shim.family='inet'
uci set firewall.nomad_shim.reload='1'

# Commit and reload firewall
uci commit firewall
/etc/init.d/firewall reload


# 3. Apply
uci commit firewall
/etc/init.d/firewall reload

# Assign Zones
WAN_ZONE=$(uci show firewall | grep -m 1 ".name='wan'" | cut -d'.' -f2)
if [ -z "$WAN_ZONE" ]; then echo "[FAIL] Could not find firewall zone named 'wan'."; exit 1; fi
uci add_list firewall.$WAN_ZONE.network='wg0'
uci add_list firewall.$WAN_ZONE.network='wg1'

# 3. COMMIT
echo "  - Committing changes..."
uci commit network
uci commit firewall

echo "--- Remote Configuration Complete ---"
