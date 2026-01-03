#!/bin/sh
# Nomad Verification Script v2 (Fixed)

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass=0
fail=0

check() {
  NAME="$1"
  CMD="$2"
  if eval "$CMD"; then
    printf "${GREEN}[PASS]${NC} %s\n" "$NAME"
    pass=$((pass + 1))
  else
    printf "${RED}[FAIL]${NC} %s\n" "$NAME"
    fail=$((fail + 1))
  fi
}

echo "--- Running Nomad State Verification v2 ---"

# 1. Package Checks (Using list-installed for reliability)
check "Package: travelmate" "opkg list-installed | grep -q '^travelmate'"
check "Package: wireguard-tools" "opkg list-installed | grep -q '^wireguard-tools'"
check "Package: nftables" "opkg list-installed | grep -q '^nftables'"

# 2. Service Checks
check "Service: nomad-monitor running" "pgrep -f /usr/bin/nomad-monitor > /dev/null"

# 3. Config Checks
# Check if wg0 exists in UCI and is set to wireguard
if [ "$(uci -q get network.wg0.proto)" = "wireguard" ]; then
  check "UCI: wg0 configured" "true"
else
  check "UCI: wg0 configured" "false"
fi

# 4. Firewall Checks
check "Firewall: Table 'nomad' loaded" "nft list tables | grep -q 'nomad'"

# 5. Routing Checks
check "Routing: Table 100 (Work) exists" "ip rule show | grep -q 'lookup 100'"
check "Routing: Table 101 (Home) exists" "ip rule show | grep -q 'lookup 101'"

echo "-------------------------------------------"
echo "Results: $pass Passed, $fail Failed."
if [ "$fail" -eq 0 ]; then
  exit 0
else
  exit 1
fi
