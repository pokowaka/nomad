#!/bin/sh
#
# Project Nomad: Remote Configuration Script (Standalone)
# This script is copied to the router and executed remotely.
# It expects WireGuard secrets and config via environment variables.

set -e
echo "--- Starting Remote Configuration (Standalone) ---"

error_count=0

# Helper to execute a command, check its exit code, and log verbosely.
check_cmd() {
    local description="$1"
    shift
    echo "  - Executing: $description"
    # Execute the command passed as arguments, suppressing its stdout/stderr for cleaner logs
    if ! "$@" >/dev/null 2>&1; then
        echo "[FAIL] Operation failed for: $description (Exit Code: $?)"
        error_count=$(expr $error_count + 1)
    else
        echo "[OK]   Success: $description"
    fi
}

# --- Clean previous config for idempotency ---
check_cmd "Delete old firewall jump rule (forward)" uci -q delete firewall.nomad_fwd_jump
check_cmd "Delete old firewall jump rule (output)" uci -q delete firewall.nomad_out_jump
check_cmd "Delete old wg0 interface" uci -q delete network.wg0
check_cmd "Delete old wg1 interface" uci -q delete network.wg1
check_cmd "Delete old firewall include" uci -q delete firewall.nomad_include
WG0_PEER_SECTION=$(uci show network | grep 'wireguard_wg0' | cut -d. -f2); if [ -n "$WG0_PEER_SECTION" ]; then check_cmd "Delete old wg0 peer" uci -q delete network."$WG0_PEER_SECTION"; fi
WG1_PEER_SECTION=$(uci show network | grep 'wireguard_wg1' | cut -d. -f2); if [ -n "$WG1_PEER_SECTION" ]; then check_cmd "Delete old wg1 peer" uci -q delete network."$WG1_PEER_SECTION"; fi

# --- Configure Interfaces and Peers ---
echo "  - Configuring WG0 (Work)..."
check_cmd "Set wg0 interface" uci set network.wg0='interface'
check_cmd "Set wg0 proto" uci set network.wg0.proto='wireguard'
check_cmd "Set wg0 private_key" uci set network.wg0.private_key="$WG0_PRIVATE_KEY"
check_cmd "Add wg0 address" uci add_list network.wg0.addresses="$WG0_ADDRESS"
check_cmd "Set wg0 mtu" uci set network.wg0.mtu='1420'
check_cmd "Set wg0 auto" uci set network.wg0.auto='0'

check_cmd "Set wg0 peer config" uci set network.wg_peer_work='wireguard_wg0'
check_cmd "Set wg0 peer public_key" uci set network.wg_peer_work.public_key="$WG0_PUBLIC_KEY"
check_cmd "Set wg0 peer endpoint_host" uci set network.wg_peer_work.endpoint_host="$WG0_ENDPOINT_HOST"
check_cmd "Set wg0 peer endpoint_port" uci set network.wg_peer_work.endpoint_port="$WG0_ENDPOINT_PORT"
check_cmd "Set wg0 peer persistent_keepalive" uci set network.wg_peer_work.persistent_keepalive='25'
check_cmd "Set wg0 peer allowed_ips" uci add_list network.wg_peer_work.allowed_ips="$WG0_ALLOWED_IPS"

echo "  - Configuring WG1 (Home)..."
check_cmd "Set wg1 interface" uci set network.wg1='interface'
check_cmd "Set wg1 proto" uci set network.wg1.proto='wireguard'
check_cmd "Set wg1 private_key" uci set network.wg1.private_key="$WG1_PRIVATE_KEY"
check_cmd "Add wg1 address" uci add_list network.wg1.addresses="$WG1_ADDRESS"
check_cmd "Set wg1 mtu" uci set network.wg1.mtu='1420'
check_cmd "Set wg1 auto" uci set network.wg1.auto='0'

check_cmd "Set wg1 peer config" uci set network.wg_peer_home='wireguard_wg1'
check_cmd "Set wg1 peer public_key" uci set network.wg_peer_home.public_key="$WG1_PUBLIC_KEY"
check_cmd "Set wg1 peer endpoint_host" uci set network.wg_peer_home.endpoint_host="$WG1_ENDPOINT_HOST"
check_cmd "Set wg1 peer endpoint_port" uci set network.wg_peer_home.endpoint_port="$WG1_ENDPOINT_PORT"
check_cmd "Set wg1 peer persistent_keepalive" uci set network.wg_peer_home.persistent_keepalive='25'
check_cmd "Set wg1 peer allowed_ips" uci add_list network.wg_peer_home.allowed_ips="$WG1_ALLOWED_IPS"

# --- Dynamically Find and Update Firewall WAN Zone ---
echo "  - Finding WAN firewall zone..."
WAN_ZONE=$(uci show firewall | grep -m 1 ".name='wan'" | cut -d'.' -f2)
if [ -z "$WAN_ZONE" ]; then echo "[FAIL] Could not find firewall zone named 'wan'. Exiting."; exit 1; fi
check_cmd "Add wg0 to WAN zone" uci add_list firewall.$WAN_ZONE.network='wg0'
check_cmd "Add wg1 to WAN zone" uci add_list firewall.$WAN_ZONE.network='wg1'

# --- Firewall: Add JUMP rules to custom chains ---
check_cmd "Create fw jump for LAN forwarding" uci set firewall.nomad_fwd_jump='rule'
check_cmd "Name fw jump for LAN" uci set firewall.nomad_fwd_jump.name='Nomad-Forward-Jump'
check_cmd "Set fw jump src" uci set firewall.nomad_fwd_jump.src='lan'
check_cmd "Set fw jump target" uci set firewall.nomad_fwd_jump.target='JUMP'
check_cmd "Set fw jump jump_target" uci set firewall.nomad_fwd_jump.jump_target='nomad_forward'
check_cmd "Set fw jump family" uci set firewall.nomad_fwd_jump.family='any'

check_cmd "Create fw jump for device output" uci set firewall.nomad_out_jump='rule'
check_cmd "Name fw jump for output" uci set firewall.nomad_out_jump.name='Nomad-Output-Jump'
check_cmd "Set fw jump src" uci set firewall.nomad_out_jump.src='device'
check_cmd "Set fw jump dest" uci set firewall.nomad_out_jump.dest='wan'
check_cmd "Set fw jump target" uci set firewall.nomad_out_jump.target='JUMP'
check_cmd "Set fw jump jump_target" uci set firewall.nomad_out_jump.jump_target='nomad_output'
check_cmd "Set fw jump family" uci set firewall.nomad_out_jump.family='any'

# --- Firewall: Add Include for Nomad Filter Script ---
check_cmd "Create firewall include" uci set firewall.nomad_include='include'
check_cmd "Set include path" uci set firewall.nomad_include.path='/etc/nftables.d/nomad-filter.nft'
check_cmd "Set include type" uci set firewall.nomad_include.fw4_compatible='1'
check_cmd "Enable include" uci set firewall.nomad_include.enabled='1'
check_cmd "Enable include reload" uci set firewall.nomad_include.reload='1'


# 3. COMMIT & APPLY
echo "  - Committing changes..."
check_cmd "Commit network changes" uci commit network
check_cmd "Commit firewall changes" uci commit firewall

echo "--- Remote Configuration Complete ---"

if [ "$error_count" -ne 0 ]; then
    echo "[FAIL] Remote configuration script finished with $error_count errors."
    exit 1
fi
