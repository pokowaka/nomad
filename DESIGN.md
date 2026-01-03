# Engineering Design: Project Nomad (Cudy TR3000)

**Version:** 4.0 (Final Architecture)
**Target Hardware:** Cudy TR3000 (MediaTek Filogic 820)
**OS:** OpenWrt 23.05+ (Ash Shell / BusyBox)

---

## 1. System Architecture
The system operates as an **Event-Driven Finite State Machine (FSM)** utilizing native OpenWrt subsystems (`netifd`, `nftables`, `libubox`) rather than heavy external dependencies.

### A. The "Cortex" (State Controller)
* **Role:** The central brain managing network state transitions.
* **Mechanism:** Hotplug Dispatcher -> Background Worker.
* **Component 1 (Dispatcher):** `/etc/hotplug.d/iface/99-nomad-controller`
    * **Logic:** Triggered by `ifup`/`ifdown`. Acquires a lock (`/var/run/nomad.lock`). Spawns the Worker. **Non-blocking.**
* **Component 2 (Worker):** `/usr/bin/nomad-monitor`
    * **Logic:** Performs connectivity checks (`travelmate`), toggles LED patterns, and executes Phase Transitions (Portal Mode <-> Secure Mode).

### B. The "Steering Wheel" (Stateful Policy Routing)
* **Role:** Maps specific LAN clients to specific Uplinks (VPNs or WAN).
* **Source of Truth:** `/etc/nomad/device_map.json`
* **Tooling:** **Strictly `jshn`** (OpenWrt native JSON library). No `sed`/`awk`/`python`.
* **Routing Logic:** Linux Policy Routing (PBR) via `ip rule` and custom Routing Tables.
    * **Table 100 (Work VPN):** Default via `wg0`. **Fallback: Unreachable (Kill Switch).**
    * **Table 101 (Home VPN):** Default via `wg1`. **Fallback: Unreachable (Kill Switch).**
    * **Table 102 (Hotel Direct):** Default via `wan`.

### C. The "Shield" (Firewall Filtering)
* **Role:** Enforces DNS security and leakage prevention.
* **Mechanism:** `nftables` include file (`/etc/nftables.d/nomad-filter.nft`).
* **Phase 1 (Portal Hunt):** Output Chain **ACCEPTS** UDP/53 (DNS) on WAN.
* **Phase 2 (Secure Mode):** Output Chain **DROPS** UDP/53 on WAN. Forces local DoT/DoH proxy.

---

## 2. File System Hierarchy (Overlay)

All custom logic resides in the overlay. The deployment script must provision these files.

```text
/
├── etc/
│   ├── config/
│   │   ├── network.safe            # Backup config (Open WiFi, DHCP enabled)
│   │   └── firewall.safe           # Backup firewall (Permissive)
│   ├── init.d/
│   │   └── 10-nomad-safemode       # Boot Script (Priority 10). Checks for Panic Flag.
│   ├── hotplug.d/iface/
│   │   └── 99-nomad-controller     # The Cortex Dispatcher
│   ├── travelmate/
│   │   └── user_hooks.sh           # Hook: triggers 'nomad-monitor' on portal success
│   ├── nftables.d/
│   │   └── nomad-filter.nft        # The Shield Rules
│   ├── nomad/
│   │   └── device_map.json         # PERSISTENT STATE (RW). Format: {"192.168.8.x": "100"}
│   └── uci-defaults/
│       └── 99-nomad-provision      # First-boot setup (enable services, set passwords)
├── usr/
│   └── bin/
│       ├── nomad-monitor           # The Cortex Worker (State Logic)
│       └── nomad-steer             # Helper: Reads JSON -> Applies 'ip rule' commands
└── www/
    └── nomad/
        ├── index.html              # Dashboard UI (Vue.js / Plain HTML)
        └── api/
            └── steering.cgi        # Sudo-enabled API. Validates Input -> Updates JSON
```

---

## 3. Critical Workflows

### Workflow A: Boot & Persistence Restoration
**Goal:** Ensure user preferences (e.g., iPad -> Home VPN) survive a reboot.
1.  **Boot:** Router initializes. Interfaces (`lan`) come up.
2.  **Trigger:** `ifup lan` fires `99-nomad-controller`.
3.  **Action:** Calls `nomad-steer restore`.
4.  **Logic (`nomad-steer`):**
    * Load `jshn` library.
    * `json_load_file /etc/nomad/device_map.json`.
    * Loop through keys (IPs).
    * Execute: `ip rule add from $IP lookup $TABLE`.

### Workflow B: The Panic Button (Atomic Recovery)
**Goal:** Recover from a bad configuration without wiping encryption keys.
1.  **Trigger:** User holds WPS Button > 5 seconds.
2.  **Action (Script):**
    * `touch /etc/nomad_safemode_active`
    * `reboot`
3.  **Boot Sequence (Pre-Network):**
    * `/etc/init.d/10-nomad-safemode` runs.
    * Detects flag file.
    * **Atomic Swap:** `cp /etc/config/network.safe /var/run/config/network` (Overlay override).
    * **LED:** Sets Red/Fast Strobe.
4.  **Restoration:** User logs in -> Clicks "Exit Safe Mode" -> Script removes flag -> Reboots.

### Workflow C: Dashboard Steering (Stateful & Atomic)
**Goal:** Move a device to a different network tier without data loss or corruption.
1.  **UI:** POST request to `/api/steering.cgi` with `{"ip": "192.168.8.145", "table": "100"}`.
2.  **Validation:** CGI script regex-validates IP and Table ID.
3.  **Atomic Write:**
    * Acquire Lock.
    * `jshn` load existing map.
    * Update key/value.
    * **Dump to Temp:** `json_dump > /tmp/device_map.tmp`.
    * **Atomic Move:** `mv /tmp/device_map.tmp /etc/nomad/device_map.json`.
    * Release Lock.
4.  **Enforcement:**
    * `ip rule del from $IP`
    * `ip rule add from $IP lookup $TABLE`
    * `conntrack -F -s $IP` (Flush connections to force new route).

---

## 4. Deployment & Verification Strategy

We do not edit files on the router. We use a **"Push" Model** from a development host.

### A. The Deployment Script (`deploy.sh`)
Must reside on the developer machine.
1.  **Packaging:** Copies `src/etc` and `src/www` to the router via SCP.
2.  **Secrets Injection:** Reads local `secrets/wg0.key` and generates a temporary UCI batch script.
3.  **Provisioning:** Runs the batch script on the router to update `/etc/config/network` and `/etc/config/firewall` without breaking hardware defaults.
4.  **Service Enablement:** Enables `travelmate`, `nomad-monitor`, `10-nomad-safemode`.

### B. The Sanity Check (`tests/verify_state.sh`)
A script pushed to the router to assert the PRD state.
* **Assert UCI:** Checks `network.wg0.proto == wireguard`.
* **Assert Process:** Checks `nomad-monitor` is running.
* **Assert Routing:** Checks `ip rule` contains `lookup 100`.
* **Assert Security:** Checks `nft list chain inet nomad output` contains the correct Drop rules.

---

## 5. Security & Safety Constraints

1.  **JSON Handling:** **MUST** use `libubox jshn`. Do not parse JSON with text tools.
2.  **Input Sanitization:** The CGI script running as root is a major attack vector. Strict Regex validation on all inputs (IPs and Table IDs) is mandatory.
3.  **Kill Switch:** The "Kill Switch" is implemented via **Unreachable Routes** in Tables 100/101. We do not rely solely on firewall rules for this; routing logic must fail closed.
4.  **Atomic Operations:** Critical state files (`device_map.json`) must never be written to directly. Always write to `/tmp/` and `mv`.