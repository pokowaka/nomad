# PRD v3.1: Cudy TR3000 "Nomad" (Refactored)

## 1. User Experience Narratives

These narratives describe the intended "Happy Path" and "Recovery Path" for the user, defining the success criteria for the engineering requirements below.

**Story A: The Hotel Arrival (The "Phone First" Workflow)**
* **Context:** The user arrives at a hotel with a hostile Captive Portal.
* **Action:** The user plugs in the router. The **System LED fast strobes (4Hz)**, indicating a portal is blocking internet access (or no WAN).
* **Workflow:**
    1.  The user ignores their Work Laptop (to prevent leaks).
    2.  The user connects their **Personal Phone** to the router's WiFi.
    3.  The router allows standard DNS temporarily to capture the portal; the user clicks "Accept" on the phone.
    4.  The router detects the successful connection, "inherits" the session, and immediately engages **Strict Security Mode**.
    5.  The router establishes the WireGuard tunnel. The **System LED slows to a Pulse (1Hz)**.
    6.  **Result:** The user opens their Work Laptop. It connects immediately to the VPN tunnel.

**Story B: The "Toxic" Spectrum (Adaptive Radio)**
* **Context:** The user is at a conference (e.g., CES in Las Vegas). The 2.4GHz spectrum is saturated.
* **Action:** The router attempts to connect to the hotel via 2.4GHz but fails to get usable throughput.
* **Workflow:**
    1.  The router's "Adaptive Strategy" logic detects high packet loss/interference on 2.4GHz.
    2.  The router automatically fails over the WAN connection to the 5GHz radio.
    3.  **Result:** The user maintains a stable, low-latency connection required for work using the shared 5GHz radio.

**Story C: The Safe Mode Recovery (The "Panic Button")**
* **Context:** The user has misconfigured a firewall rule and locked themselves out.
* **Action:** The user presses and holds the **WPS Button for 5 seconds**.
* **Workflow:**
    1.  The router runs the `panic_restore` script.
    2.  Network interfaces and Firewall rules revert to defaults (Open WiFi, standard IP).
    3.  **Crucially:** The user's WireGuard keys and installed packages are **NOT** deleted.

**Story D: The "Nomad Dashboard" (Per-Device Routing)**
* **Context:** The user wants to watch Netflix on their iPad (needs Home IP) while the Work Laptop stays on the Corporate VPN.
* **Action:** The user opens a browser on the iPad and navigates to `nomad.lan` (or the gateway IP).
* **Workflow:**
    1.  **Identification:** The dashboard recognizes the device. It is currently on "Hotel Direct" (Default).
    2.  **Selection:** The user clicks **[ Connect to Home VPN ]**.
    3.  **Routing:** The router updates the routing table for that IP. The iPad is now on the Home VPN.
    4.  **Kill Switch Event:** If the Home VPN drops, the iPad loses internet access completely. It does *not* leak back to the Hotel WAN. The user must re-visit `nomad.lan` to fix it or switch profiles.

---

## 2. Executive Summary

**Objective:** Deploy the Cudy TR3000 as a hardened, low-profile travel gateway. The device prioritizes friction-free "Headless Operation" for the user while enforcing a zero-trust security posture against hostile ISPs via TTL mangling and encrypted DNS.

## 3. Prioritized Feature List

### P0: Hardened Connectivity (Critical Path)

**Headless "Assisted" Authentication**
* **Context:** Fully automated "Zero-Touch" is not viable due to diverse captive portal technologies.
* **Implementation:** `travelmate` detects the portal state.
* **Notification:** **LED Pattern Only.** No external messages (Telegram/Email) are sent during the disconnected state.
* **Mechanism:** The first connected LAN client is passed through to authenticate; the router subsequently inherits the authenticated session (MAC cloning/session inheritance).

**Stealth Layer (Traffic Masking)**
* **TTL Normalization:** Outgoing WAN packets are rewritten to `65` (IPv4) or `HL` adjusted to mask the presence of a router/NAT to the ISP.
* **Encrypted DNS (DoH/DoT) with "Portal Exception":**
    - *Phase 1 (Not Connected/Portal):* Standard UDP/53 is **Allowed** to facilitate Captive Portal redirection and login.
    - *Phase 2 (Connected/Secure):* Once `travelmate` confirms internet connectivity, **Strict Enforcement** activates. All UDP/53 is dropped. DNS is forced via `https-dns-proxy` or `stubby` (DoT/DoH).

**Multi-WAN Failover ( `mwan3` )**
* **Priority 1:** WISP (Repeater Mode) - Primary hotel link.
* **Priority 2:** Ethernet WAN - Wired backhaul (if available).
* **Priority 3:** USB Tethering (iOS/Android) - Emergency backup.

**Emergency Fail-Safe ("The Panic Button")**
* **Input:** **WPS Button** (distinct from Reset).
* **Trigger:** Long Press (5s).
* **Action:** Reverts firewall, network, and wireless configurations to a known "Safe Mode" (Open WiFi on LAN, static IP `192.168.8.1`).
* **Safety:** Explicitly **preserves** `/etc/wireguard` keys and installed packages.

### P1: VPN & Routing (The "Nomad Dashboard")

**The "Nomad" Control Plane**
* **Requirement:** A lightweight, mobile-friendly web interface hosted locally (e.g., `http://nomad.lan`).
* **Function:** Allows any connected client to self-select their upstream gateway.
* **Policies:**
    1.  **Work VPN (Default for Laptop):** Full Tunnel via `WG0`. Strict Kill Switch.
    2.  **Home VPN:** Split Tunnel via `WG1`. Strict Kill Switch.
    3.  **Hotel Direct (Default for Personal):** Clear internet access. Used for casual browsing and Captive Portal clearance.

**Kill Switch (Profile-Based Enforcement)**
* **Logic:** The "Kill Switch" is attached to the *Profile*, not just the device.
* **Behavior:**
    - If **Work VPN** is selected and fails -> **Block Traffic.**
    - If **Home VPN** is selected and fails -> **Block Traffic.**
    - *Constraint:* Traffic will never silently failover to a less secure tier (e.g., VPN -> Clear Net). The user must explicitly re-select "Hotel Direct" in the dashboard to restore connectivity if the VPN is permanently down.

### P2: Hardware IO & Feedback

**WPS Button Logic (Contextual Control)**
* **Short Press (<2s):** Triggers `travelmate` re-scan (e.g., if moving rooms).
* **Long Press (>5s):** Triggers P0 Emergency Fail-Safe (Network Reset).

**LED Feedback (Sanity Check)**
* *Constraint:* Utilizing the standard System/Internet LED (GPIO control verified).
* **Solid On:** Internet Connected.
* **Slow Pulse (1Hz):** At least one VPN Tunnel is Up.
* **Fast Strobe (4Hz):** Not Ready / Captive Portal Detected / No WAN.

### P3: Radio Discipline (Throughput Optimization)

**Adaptive Split-Band Strategy**
* **Goal:** Maximize throughput where possible, but prioritize connectivity above all.
* **Logic:**
    1.  **Scanning:** `travelmate` scans both 2.4GHz and 5GHz bands for known SSIDs.
    2.  **Preference (Soft Lock):** If both bands are available with similar signal strength (RSSI), prefer 2.4GHz for WAN to preserve the 5GHz radio for exclusive LAN usage (Split-Band).
    3.  **Failover:** If 2.4GHz is unusable (high interference) or unavailable, allow WAN connection on 5GHz.
* **Consequence:**
    - *Ideal State:* WAN on 2.4GHz / LAN on 5GHz (100% Throughput).
    - *Fallback State:* WAN on 5GHz / LAN on 5GHz (50% Throughput due to radio time-slicing, but reliable connection).

## 4. Engineering Implementation Plan (Phase 1)

* **Hardware:** Cudy TR3000 (MediaTek Filogic 820).
* **Base Image:** OpenWrt 23.05 (Stable).
* **Critical Packages:**
    

```text
    travelmate
    mwan3
    wireguard-tools
    pbr
    kmod-usb-net-ipheth
    iptables-mod-ipopt
    https-dns-proxy
    kmod-leds-gpio
    uhttpd
    luci-mod-rpc
    ```
