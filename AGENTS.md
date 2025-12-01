# Agent Instructions: Privacy Router Deployment

You are assisting a user in deploying a network-wide VPN privacy router. This document provides your operational framework.

> **Development Note:** This stack was developed, tested, and deployed using **Claude Opus 4.5** via Claude Code with **Mullvad VPN**. The methodology below reflects lessons learned during that implementation.

## Your Mission

Help the user deploy a privacy router that:
1. Routes ALL network traffic through an encrypted VPN tunnel
2. Implements a firewall-based kill switch (no traffic leaks)
3. Automatically recovers from failures
4. **Optional:** DNS-level ad/tracker blocking (AdGuard Home)
5. **Optional:** Threat intelligence blocking (BanIP)

---

## Information Discovery Hierarchy

**All placeholder values in examples (YOUR_*, VPN_PROVIDER_*, etc.) must be resolved. Use this priority order:**

### 1. Local Discovery (Preferred)
Probe the user's environment automatically where possible:
```
- Network topology: ip addr, ip route, /etc/config/network
- Interface names: ip link, ls /sys/class/net/
- Current gateway/DNS: cat /etc/resolv.conf, ip route show default
- DHCP leases: cat /tmp/dhcp.leases
- Firewall state: iptables -L -n, uci show firewall
- Existing configs: /etc/amneziawg/, /etc/config/
```

### 2. User Input (Secrets Only)
**When a secret is needed, always ask for user consent first.**

The primary secret is the **VPN private key** from the user's provider account.

**Consent flow (when deployment requires a secret):**

1. **Agent asks permission:** "I need your VPN private key to configure the tunnel. How would you like to proceed?"

2. **User chooses one of:**
   - **Option A:** "I've put it in `secrets.env`" → Agent reads from file
   - **Option B:** "Here it is: [key]" → User pastes directly in chat
   - **Option C:** "I'll enter it manually" → Agent provides file path and field name

3. **Agent proceeds** only after user consents and provides the secret via their chosen method

**Option A: secrets.env (convenience file)**

For users who prefer to prepare secrets in advance:

```bash
cp secrets.env.example secrets.env
nano secrets.env  # Fill in VPN_PRIVATE_KEY
```

Contents:
```
VPN_PRIVATE_KEY=           # Required - from VPN provider account
# ROUTER_ADMIN_PASSWORD=   # Optional - OpenWrt admin
# ADGUARD_ADMIN_PASSWORD=  # Optional - AdGuard admin
```

> **Note:** This is NOT a traditional `.env` file loaded into app environment variables.
> It's a **secrets reference file** - the agent reads values during deployment and
> injects them into configuration files (e.g., `awg0.conf`). No runtime environment
> variables are involved. The file is gitignored - secrets never leave user's machine.

**Option C: Manual entry**

If user declines agent handling, provide clear instructions:
```
File: /etc/amneziawg/awg0.conf
Field: PrivateKey = <paste your key here>
```

Do NOT prompt for values that can be discovered or researched (IPs, public keys, endpoints).

### 3. Deep Research (Current/External Values)
Use web research for values requiring up-to-date discovery:
```
- VPN server endpoints (IPs, ports, public keys)
- VPN provider DNS IPs (may change)
- Provider-specific configuration requirements
- Current best practices and security advisories
```

**Examples of what to discover vs. ask:**

| Value | Discovery Method |
|-------|-----------------|
| WAN interface name | `ip link` or `uci show network` |
| LAN IP scheme | `ip addr show br-lan` |
| AdGuard IP | Check DHCP config or ask user preference |
| Mullvad server IP | Research current server list |
| Mullvad public key | Research or download from provider |
| User's private key | **ASK** - this is a secret |
| VPN provider DNS | Research provider documentation |

**The goal:** Minimize user prompts. Discover what's discoverable, research what's public, ask only for secrets (with user consent).

---

## Phase 1: Network Audit

**Before any implementation, gather this information:**

### 1.1 Current Network Topology

Ask the user or probe their system to determine:

```
□ ISP connection type (fiber ONT, cable modem, DSL, LTE/5G)
□ Current router model and capabilities
□ Current IP scheme (e.g., 192.168.1.0/24)
□ Number and types of devices on network
□ Any existing VLANs or network segmentation
□ Static IP assignments that must be preserved
```

### 1.2 Deployment Method

**This is a decision point requiring user confirmation. Recommend based on audit findings.**

All options provide the **same core protection**: AmneziaWG obfuscation, AdGuard DNS filtering, kill switch, and watchdog recovery. The choice is about deployment architecture, not features.

| Option | What You're Deploying | What Happens to Existing Router |
|--------|----------------------|--------------------------------|
| **A: Dedicated Hardware** | Full router OS (OpenWrt) | Becomes WiFi access point only |
| **B: Virtual Machine** | Full router OS (OpenWrt) | Becomes WiFi access point only |
| **C: Docker Container** | VPN gateway only (Alpine) | Keeps all current functions |

**Options A & B (OpenWrt - Full Router Replacement):**
- Deploys a complete router operating system
- OpenWrt handles everything: routing, DHCP, DNS, firewall, VPN
- Existing router becomes just a WiFi access point
- This IS the network's router
- Requires dedicated hardware or VM with 2 NICs

**Option C (Docker - VPN Gateway Add-on):**
- Deploys just the VPN tunnel + kill switch
- Runs on existing Linux server, NAS, or VM
- Existing router keeps doing DHCP, WiFi, routing
- Devices opt-in by pointing their gateway/DNS at the container
- Does NOT replace your router

```
Network topology difference:

Option A/B: Modem → [OpenWrt Privacy Router] → WiFi AP → All Devices Protected
Option C:   Modem → [Existing Router] → Devices
                           ↓
                    [Docker on Server/NAS]
                    (only devices pointing here are protected)
```

**Recommendation logic:**

```
IF user explicitly asks for Docker:
   → Option C

IF user wants to add VPN to existing router (but doesn't specify how):
   → Clarify: "Do you want this as a Docker container or a VM?"
   → Either could be appropriate depending on their setup

IF user is unsure or confused:
   → Explain the architectural difference (router replacement vs add-on)
   → RECOMMEND OpenWrt (Option A or B based on hardware)
   → "I recommend the dedicated privacy router approach - it protects your
      entire network automatically and is the most straightforward setup."

IF user has spare Pi/mini-PC:
   → RECOMMEND Option A (dedicated hardware)
```

**Default recommendation is OpenWrt** — it's the optimal choice for most users. Docker is for users who explicitly want to add VPN capability to their existing router stack and know they want the container approach.

**Hardware requirements:**
- **Options A/B:** Device needs TWO network interfaces (WAN + LAN). Single-NIC devices need USB Ethernet adapter.
- **Option C:** Any Docker host with macvlan support. See [docker/README.md](docker/README.md).

### 1.3 VPN Provider Configuration

**Autonomous where possible, respect user privacy for secrets.**

1. **Determine provider** — Ask if not known: "Which VPN provider do you use?"
2. **Research provider automatically** — WireGuard support, config format, server list
3. **Handle secrets appropriately** — See below

**Handling secrets (private keys, credentials):**

Before asking user to share any secrets, ask if they're comfortable:
```
"Your VPN config contains a private key. I can help in two ways:
 1. You paste the config here and I'll set everything up automatically
 2. You prefer to input secrets yourself - I'll generate the config with
    placeholders and tell you exactly where to fill them in

Which do you prefer?"
```

- If user is comfortable → parse config, extract values, deploy automatically
- If user prefers privacy → generate config template, guide them to fill in secrets directly on the target system

**What you research/derive automatically (no user input needed):**
- Provider's WireGuard support and config format
- Server IPs (resolve hostnames)
- Provider DNS servers
- AmneziaWG obfuscation parameters (use defaults from this repo)

**If user hasn't chosen a provider:** Recommend Mullvad (see README for rationale).

**If user is in a high-censorship region:** WireGuard/AmneziaWG may be insufficient. Research current obfuscation methods and advise accordingly.

**For Mullvad users:**
- Config page: https://mullvad.net/en/account/wireguard-config
- Server list: https://mullvad.net/en/servers
- DNS servers: See DNS table in Mullvad-Specific section

### 1.4 Special Requirements

```
□ Devices that need VPN bypass (gaming consoles, work devices)
□ Services that need port forwarding
□ Bandwidth requirements
□ IPv6 requirements (recommend: disable)
```

### 1.5 Optional Addons

**Ask the user which optional features they want:**

```
□ AdGuard Home - DNS-level ad/tracker blocking, encrypted DNS (DoH)
□ BanIP - Threat intelligence, blocks known malicious IPs
□ Neither - Basic VPN routing only (still fully functional)
```

> **Note:** The core privacy router works without any addons. AdGuard and BanIP enhance security but add complexity. Recommend for technical users; skip for simplicity.

---

## Phase 2: Diagnostic Commands

If user provides SSH access to their current network or target device, run these diagnostics:

### Network State

```bash
# Current routing
ip route show
ip addr show

# DNS configuration
cat /etc/resolv.conf
nslookup google.com

# Firewall state (OpenWrt)
uci show firewall
iptables -L -n -v 2>/dev/null || nft list ruleset

# Interface configuration (OpenWrt)
uci show network
uci show dhcp
```

### Connectivity Tests

```bash
# Basic internet
ping -c 3 8.8.8.8
ping -c 3 google.com

# Check for IPv6 leaks
curl -6 https://ipv6.icanhazip.com 2>/dev/null && echo "WARNING: IPv6 active"

# Current public IP
curl -s https://ipinfo.io/ip
```

### Hardware Detection

```bash
# Available interfaces
ip link show
ls /sys/class/net/

# CPU/Memory
cat /proc/cpuinfo | grep -E "model name|processor" | head -4
free -h

# Storage
df -h
```

---

## Phase 3: Implementation Planning

Based on audit results, create a customized plan using these references:

| Document | Use For |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Understanding component relationships |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Step-by-step installation (Options A & B) |
| [docker/README.md](docker/README.md) | Docker deployment (Option C) |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Config file syntax and options |
| [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | Deep technical understanding |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | When things go wrong |
| [docs/OPTIONAL_ADDONS.md](docs/OPTIONAL_ADDONS.md) | AdGuard Home, BanIP setup details |

### Implementation Templates

> **CRITICAL: These are EXAMPLES, not drop-in solutions.**
>
> Every script and config must be adapted to the user's unique environment:
> 1. **Research** - Validate assumptions (network topology, provider specifics, hardware)
> 2. **Adapt** - Modify placeholders AND logic to fit user's scenario
> 3. **Test** - Verify each component before proceeding to the next
>
> Never assume example values are correct for the user's setup.

### Autonomous Operation Philosophy

**This stack is designed to be "vibe coded" — deploy with minimal user input.**

**Your job as an agent:**
1. **Audit autonomously** — Probe the network, detect topology, identify existing infrastructure
2. **Recommend OpenWrt by default** — Docker only if user explicitly requests it
3. **Guide user through VPN config retrieval** — Ask which provider, research how that provider delivers config files, guide user to retrieve them. If user consents to share secrets in chat, parse configs automatically; otherwise guide them to input secrets directly on target system
4. **Generate configs** — Derive network values from audit; handle secrets per user preference (auto-parse or placeholders)
5. **Deploy with self-correction** — Test, detect failures, diagnose, fix without asking user

**Calibrate to user's experience level:**
- **Start by assuming inexperience** — explain concepts, offer guidance
- **Adjust based on responses** — if user demonstrates understanding, reduce hand-holding
- **Respect informed input** — if user knows what they want and why, don't second-guess

**Minimal user decision points:**
- "Which VPN provider?" (always ask, don't infer)
- Secrets handling preference (share in chat vs input directly)
- High-level preferences when genuinely ambiguous

**NOT acceptable:**
- Asking user for IP addresses you can discover
- Asking user for technical values you can derive
- Asking user to "confirm" values you already validated
- Multi-step Q&A for information that should be automated

**Example of CORRECT autonomous operation:**
```
User: "Set up my network with VPN protection"

Agent: [Audits network topology via SSH/API]
       "I found your network: 192.168.1.0/24, router at .1, server 'nas-01' at .50.
        Since you have a capable server, I'll deploy the Docker VPN gateway.

        Which VPN provider do you use? (Or I can set up Mullvad - recommended)"

User: "I have Mullvad"

Agent: [Guides user through Mullvad login to generate WireGuard config]
       "Please log into mullvad.net and go to WireGuard config page.
        I'll wait while you download the config file..."

User: [uploads/pastes config file]

Agent: [Parses config, extracts all values, selects optimal server]
       "Got it. Deploying to nas-01 with Stockholm exit server.
        [Deploys automatically, tests, confirms working]

        Done. All traffic now routes through VPN. Kill switch active.
        Test: https://am.i.mullvad.net/connected"
```

### Template Reference

Use these example configs, substituting user-specific values:

| Template | Location | Tested | Notes |
|----------|----------|:------:|-------|
| **Core (Required)** | | | |
| Secrets file | `secrets.env.example` | ✓ | VPN private key, admin passwords |
| Network interfaces | `openwrt/network/interfaces.example` | ✓ | Generic OpenWrt |
| Firewall zones (full) | `openwrt/firewall/zones.example` | ✓ | Complete firewall config |
| Firewall VPN zone | `openwrt/firewall-vpn-zone.example` | ✓ | VPN zone + kill switch only |
| DHCP config | `openwrt/dhcp/dhcp.example` | ✓ | DNS push to clients |
| VPN tunnel (generic) | `openwrt/amneziawg/awg0.conf.example` | ✓ | Any WireGuard provider |
| VPN tunnel (Mullvad) | `openwrt/amneziawg/mullvad-awg0.conf.example` | ✓ | Mullvad-optimized |
| **Watchdog (failover)** | `openwrt/amneziawg/awg-watchdog.sh` | ✓ | Multi-server failover + failback |
| Server list (failover) | `openwrt/amneziawg/servers.conf.example` | ✓ | For failover watchdog |
| Hotplug script | `openwrt/amneziawg/99-awg.hotplug` | ✓ | WAN-up auto-start |
| **Init script (OpenWrt)** | `openwrt/amneziawg/awg-watchdog.init` | ✓ | Boot persistence (procd) |
| **Systemd service (watchdog)** | `scripts/awg-watchdog.service` | ✓ | Linux systemd (non-OpenWrt) |
| Cron jobs | `openwrt/crontab.example` | ✓ | Scheduled tasks template |
| IPv6 disable (kernel) | `openwrt/sysctl-ipv6-disable.conf` | ✓ | sysctl.conf additions |
| **Optional Addons (ask user in 1.5)** | | | |
| AdGuard Home (generic) | `adguard/AdGuardHome.yaml.example` | ✓ | Any upstream DNS |
| AdGuard Home (Mullvad) | `adguard/mullvad-AdGuardHome.yaml.example` | ✓ | Mullvad DoH |
| Systemd service (AdGuard) | `scripts/adguardhome.service` | ✓ | Linux systemd |
| BanIP config | `openwrt/banip/banip.example` | | Threat intelligence |
| **Utility Scripts** | | | |
| Firewall setup | `scripts/setup-firewall.sh` | ✓ | One-command VPN zone setup |
| IPv6 disable | `scripts/disable-ipv6.sh` | ✓ | Complete IPv6 hardening |
| Config backup | `scripts/auto-backup.sh` | ✓ | Daily /etc/config backup |
| Log rotation | `scripts/rotate-watchdog-log.sh` | ✓ | Watchdog log rotation |
| **Docker (Option C)** | | | |
| Dockerfile | `docker/Dockerfile` | ✓ | Multi-stage, builds amneziawg-go |
| Compose file | `docker/docker-compose.yml` | ✓ | macvlan + AdGuard sidecar |
| Environment template | `docker/.env.example` | ✓ | All required variables |
| VPN config | `docker/config/awg0.conf.example` | ✓ | Container VPN template |
| Kill switch | `docker/config/postup.sh` | ✓ | iptables DROP policy |
| Entrypoint | `docker/scripts/entrypoint.sh` | ✓ | Container startup |
| Health check | `docker/scripts/healthcheck.sh` | ✓ | 5-layer health validation |
| Watchdog | `docker/scripts/watchdog.sh` | ✓ | Auto-recovery daemon |
| Test suite | `docker/scripts/test-suite.sh` | ✓ | 10 comprehensive tests |
| Quick test | `docker/scripts/quick-test.sh` | ✓ | Fast daily validation |
| Docker README | `docker/README.md` | ✓ | Container-specific setup |

> **Tested column:** ✓ = Production-tested. OpenWrt on Raspberry Pi 5 (23.05, Mullvad). Docker on amd64 + arm64.

---

## Phase 4: Execution Checklist

> **Docker users (Option C):** Skip this phase. Follow [docker/README.md](docker/README.md) instead, then proceed to Phase 5 for validation tests. The Docker implementation includes built-in test scripts (`quick-test.sh`, `test-suite.sh`).

**For Options A & B (OpenWrt):** Guide the user through these steps, verifying each before proceeding:

### 4.1 Base System

```
□ OpenWrt installed and accessible via SSH
□ Two network interfaces identified (WAN and LAN)
□ Basic internet connectivity working
□ Package manager functional (opkg update)
```

### 4.2 VPN Setup

```bash
# Install AmneziaWG packages
opkg update
opkg install kmod-crypto-lib-chacha20 kmod-crypto-lib-chacha20poly1305 \
             kmod-crypto-lib-curve25519 kmod-udptunnel4 kmod-udptunnel6

# Download pre-built packages from:
# https://github.com/amnezia-vpn/amneziawg-openwrt/releases

opkg install /tmp/kmod-amneziawg_*.ipk
opkg install /tmp/amneziawg-tools_*.ipk
```

**Verification:**
```
□ AmneziaWG packages installed (kmod-amneziawg, amneziawg-tools)
□ Config file created at /etc/amneziawg/awg0.conf
□ Permissions set (chmod 600)
□ Manual tunnel test successful (optional if using watchdog*)
□ VPN exit IP confirmed
```

> *The watchdog scripts handle route setup automatically. Manual testing (see Quick Reference at end) is useful for troubleshooting but not required if proceeding directly to Section 4.5 (Reliability).

**Mullvad verification:**
```bash
# Check if connected to Mullvad
curl -s https://am.i.mullvad.net/connected
# Expected: "You are connected to Mullvad"

# Get exit IP
curl -s https://am.i.mullvad.net/ip
```

### 4.3 Kill Switch

```bash
# Create VPN zone
uci set firewall.vpn=zone
uci set firewall.vpn.name='vpn'
uci set firewall.vpn.device='awg0'
uci set firewall.vpn.input='REJECT'
uci set firewall.vpn.output='ACCEPT'
uci set firewall.vpn.forward='REJECT'
uci set firewall.vpn.masq='1'
uci set firewall.vpn.mtu_fix='1'

# Allow LAN to VPN forwarding ONLY
uci set firewall.lan_vpn=forwarding
uci set firewall.lan_vpn.src='lan'
uci set firewall.lan_vpn.dest='vpn'

# Commit
uci commit firewall
/etc/init.d/firewall restart
```

**Verification:**
```
□ VPN firewall zone created
□ LAN→VPN forwarding enabled
□ NO LAN→WAN forwarding exists
□ Kill switch tested (ip link set awg0 down → no internet)
```

### 4.3.1 DNS Hijack Prevention (Recommended)

Prevents devices from bypassing your DNS server with hardcoded addresses (e.g., 8.8.8.8):

```bash
# Block external DNS except from your DNS server (AdGuard/Pi-hole IP)
# Change 192.168.1.5 to your AdGuard/DNS server IP

uci add firewall rule
uci set firewall.@rule[-1].name='Block-External-DNS-TCP'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='vpn'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='REJECT'
uci set firewall.@rule[-1].family='ipv4'
uci set firewall.@rule[-1].src_ip='!192.168.1.5'

uci add firewall rule
uci set firewall.@rule[-1].name='Block-External-DNS-UDP'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='vpn'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='REJECT'
uci set firewall.@rule[-1].family='ipv4'
uci set firewall.@rule[-1].src_ip='!192.168.1.5'

uci commit firewall
/etc/init.d/firewall restart
```

**Why:** Smart TVs, IoT devices, and some apps bypass local DNS by hardcoding Google (8.8.8.8) or Cloudflare (1.1.1.1). This rule forces all DNS through your local server, ensuring ad blocking and privacy protection apply to all devices.

**Verification:**
```
□ DNS hijack rules added (iptables -L -n | grep 53)
□ Test: nslookup google.com 8.8.8.8 from client → should fail/timeout
□ Test: nslookup google.com (via local DNS) → should work
```

### 4.4 DNS

**If user chose AdGuard Home (from 1.5):**

For Mullvad users, configure AdGuard upstream DNS:
```yaml
upstream_dns:
  - https://adblock.dns.mullvad.net/dns-query  # With ad blocking
  # OR
  - https://dns.mullvad.net/dns-query  # Without ad blocking
```

Verification (with AdGuard):
```
□ AdGuard Home installed and running
□ Upstream DNS set to DoH (VPN provider)
□ DHCP pushing AdGuard IP to clients
□ DNS resolution working through AdGuard
□ Ad blocking verified (nslookup doubleclick.net → 0.0.0.0)
```

**If user chose NO AdGuard (basic setup):**

Configure OpenWrt to use VPN provider's DNS directly:
```bash
# Set router's own DNS resolver (for router itself)
# Mullvad: 100.64.0.4 | IVPN: 10.0.254.1 | Proton: 10.2.0.1
uci set network.lan.dns='VPN_PROVIDER_DNS_IP'
uci commit network

# Push DNS to DHCP clients
uci add_list dhcp.lan.dhcp_option='6,VPN_PROVIDER_DNS_IP'
uci commit dhcp
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
```

Verification (without AdGuard):
```
□ DNS resolves through VPN tunnel
□ nslookup google.com returns result
□ DNS not leaking (test at dnsleaktest.com through VPN)
```

### 4.5 Reliability

**Watchdog with failover** (`openwrt/amneziawg/awg-watchdog.sh`):

**For OpenWrt (procd):**
```
□ Copy awg-watchdog.sh to /etc/awg-watchdog.sh
□ Configure VPN_IP (your provider-assigned internal IP)
□ Create server list: /etc/amneziawg/servers.conf
□ Copy awg-watchdog.init to /etc/init.d/awg-watchdog
□ Enable: /etc/init.d/awg-watchdog enable && start
```

**For standard Linux (systemd):**
```
□ Copy awg-watchdog.sh to /etc/awg-watchdog.sh
□ Configure VPN_IP (your provider-assigned internal IP)
□ Create server list: /etc/amneziawg/servers.conf
□ Copy scripts/awg-watchdog.service to /etc/systemd/system/
□ systemctl daemon-reload
□ systemctl enable --now awg-watchdog
```

Read `awg-watchdog.sh` — it's well-commented and explains all configuration options and behavior.

**servers.conf format:**
```
# Format: NAME ENDPOINT_IP PORT PUBLIC_KEY
# First server = primary (watchdog failsback to it)

# PUBLIC KEY RULES:
# - First server: Specify the actual public key from awg0.conf
# - Same-city servers: Use "-" (inherits from base config)
# - Different cities: MUST specify that city's public key!

# Example: All same city (LAX cluster) - can use "-" after first
us-lax-wg-001   203.0.113.10    51820   AbCdEfGh...your_key_here
us-lax-wg-002   203.0.113.11    51820   -
us-lax-wg-003   203.0.113.12    51820   -

# WRONG: Mixing cities with "-" will FAIL (different keys!)
# us-sjc-wg-001   198.51.100.10   51820   -   # ✗ Different city, needs its own key!
```

Guidelines:
- Add 3-5 servers from **same city/region** for simplest config
- If mixing cities, get each city's public key from your VPN provider
- Get server IPs by resolving hostnames (not the hostname itself!)
- See `servers.conf.example` for full documentation and examples

**Failover behavior:**
- Monitors connectivity by pinging through tunnel
- After 3 consecutive failures → switches to next server
- Cycles through all servers until one works
- After 10 successful checks → attempts failback to primary
- Kill switch maintained during failover (no traffic leaks)

**Other reliability components:**
```
□ Hotplug script installed (auto-start on WAN up)
□ Boot persistence configured (init.d or systemd)
□ IPv6 disabled at all levels (see openwrt/sysctl-ipv6-disable.conf)
□ Optional: scripts/auto-backup.sh for daily config backup
□ Optional: scripts/rotate-watchdog-log.sh for log rotation
□ Optional: cron jobs (openwrt/crontab.example)
```

**Utility scripts** (copy to /etc/ and add to cron):
- `scripts/setup-firewall.sh` - One-command VPN zone setup
- `scripts/disable-ipv6.sh` - Complete IPv6 hardening (kernel + UCI)
- `scripts/auto-backup.sh` - Daily /etc/config backup with rotation
- `scripts/rotate-watchdog-log.sh` - Watchdog log rotation

### 4.6 Cutover

**Basic cutover checklist:**
```
□ Existing router set to AP/bridge mode
□ Cables connected: Modem → Privacy Router → WiFi AP
□ All devices receiving new DHCP leases
□ Full connectivity test from multiple devices
```

#### 4.6.1 Pre-Located Setup Cutover (Optional)

> **When to use:** If you configured and tested the router BEFORE physically relocating it to sit between the modem and network (recommended approach for complex setups). Skip if you deployed directly in final position.

**This approach allows:**
- Full configuration and testing while existing network remains functional
- Validation of all components before disrupting production network
- Easier troubleshooting (existing internet still works)

**Pre-cutover audit (run from router before relocating):**
```bash
echo "=== Pre-Cutover Configuration Audit ==="

# 1. Firewall hardening
echo -n "drop_invalid: "; uci get firewall.@defaults[0].drop_invalid
echo -n "syn_flood: "; uci get firewall.@defaults[0].syn_flood

# 2. Kill switch (no LAN→WAN forwarding)
echo "LAN→VPN forwarding:"
uci show firewall | grep -E "forwarding.*src.*lan.*dest.*vpn" && echo "  ✓ Present" || echo "  ✗ MISSING"
echo "LAN→WAN forwarding (should be empty):"
uci show firewall | grep -E "forwarding.*src.*lan.*dest.*wan" && echo "  ✗ EXISTS - KILL SWITCH BROKEN" || echo "  ✓ None (kill switch intact)"

# 3. DNS configuration
echo -n "DHCP DNS option: "; uci get dhcp.lan.dhcp_option

# 4. DNS hijack prevention
uci show firewall | grep -q "Block-External-DNS" && echo "DNS hijack prevention: ✓ Present" || echo "DNS hijack prevention: ✗ MISSING"

# 5. VPN tunnel status
amneziawg show awg0 | grep -E "interface|latest handshake" || wg show awg0 | grep -E "interface|latest handshake"

# 6. Watchdog status
/etc/init.d/awg-watchdog enabled && echo "Watchdog auto-start: ✓ Enabled" || echo "Watchdog auto-start: ✗ Disabled"
pgrep -f "awg-watchdog" > /dev/null && echo "Watchdog running: ✓ Yes" || echo "Watchdog running: ✗ No"

# 7. Current IP (will change at cutover)
echo -n "Current LAN IP: "; uci get network.lan.ipaddr
```

**Expected output (all should pass):**
```
drop_invalid: 1
syn_flood: 1
LAN→VPN forwarding:
  ✓ Present
LAN→WAN forwarding (should be empty):
  ✓ None (kill switch intact)
DHCP DNS option: 6,YOUR_DNS_IP
DNS hijack prevention: ✓ Present
interface: awg0
  latest handshake: X seconds ago
Watchdog auto-start: ✓ Enabled
Watchdog running: ✓ Yes
Current LAN IP: 192.168.1.X (temporary IP)
```

**Physical cutover steps:**

1. **Set existing router to AP mode FIRST** (before touching privacy router)
   - Access existing router admin panel
   - Enable AP/Bridge mode (disables DHCP, NAT, firewall)
   - Assign static IP (e.g., 192.168.1.4) so you can still access it
   - Save and wait for reboot

2. **Relocate privacy router**
   - Power off privacy router
   - Connect: `Modem/ONT → Privacy Router WAN port`
   - Connect: `Privacy Router LAN port → Existing Router (now AP)`
   - Power on privacy router

3. **Change privacy router IP to gateway address**
   ```bash
   # SSH may disconnect - have console access ready if virtualized
   uci set network.lan.ipaddr='192.168.1.1'
   uci commit network
   /etc/init.d/network restart
   ```

4. **Verify from client device**
   - Disconnect/reconnect WiFi to get new DHCP lease
   - Check gateway is now privacy router: `ip route` or network settings
   - Visit https://am.i.mullvad.net (or your VPN's check page)
   - Verify DNS filtering: `nslookup doubleclick.net` should return 0.0.0.0

**Rollback if cutover fails:**
```
1. Power off privacy router
2. Reconnect modem directly to existing router
3. Set existing router back to Router mode (re-enable DHCP)
4. Debug privacy router separately before retry
```

---

## Phase 5: Validation Tests

After deployment, run comprehensive verification. **Do not consider deployment complete until all tests pass.**

### 5.1 Quick Functional Tests

**Docker users (Option C):** Use the built-in test scripts:
```bash
# Quick validation (5 tests, ~10 seconds)
docker exec privacy-router /opt/scripts/quick-test.sh

# Full test suite (10 tests, includes kill switch verification)
docker exec privacy-router /opt/scripts/test-suite.sh
```

**OpenWrt users (Options A & B):** Run these manually:

```bash
# VPN active (Mullvad)
curl -s https://am.i.mullvad.net/connected
# Expected: "You are connected to Mullvad"

# For other providers, check exit IP
curl -s https://ipinfo.io/ip
# Expected: VPN exit IP, not ISP IP

# Kill switch working
ip link set awg0 down
curl -s --connect-timeout 5 https://google.com || echo "PASS: Kill switch active"
ip link set awg0 up

# DNS filtering
nslookup doubleclick.net
# Expected: 0.0.0.0 or NXDOMAIN

# No IPv6 leaks
curl -6 --connect-timeout 5 https://ipv6.icanhazip.com 2>/dev/null || echo "PASS: No IPv6"

# No DNS leaks
# Visit: https://dnsleaktest.com from a client device
```

### 5.2 Comprehensive Configuration Audit

**Audit deployed config against repo templates to ensure nothing was missed:**

```bash
echo "=========================================="
echo "COMPREHENSIVE CONFIGURATION AUDIT"
echo "=========================================="

# ===== FIREWALL DEFAULTS =====
echo -e "\n[1/8] Firewall Defaults"
echo "---"
drop_inv=$(uci get firewall.@defaults[0].drop_invalid 2>/dev/null)
syn_flood=$(uci get firewall.@defaults[0].syn_flood 2>/dev/null)
input=$(uci get firewall.@defaults[0].input 2>/dev/null)
forward=$(uci get firewall.@defaults[0].forward 2>/dev/null)

[ "$drop_inv" = "1" ] && echo "✓ drop_invalid: enabled" || echo "✗ drop_invalid: MISSING (add: uci set firewall.@defaults[0].drop_invalid='1')"
[ "$syn_flood" = "1" ] && echo "✓ syn_flood: enabled" || echo "✗ syn_flood: MISSING"
[ "$input" = "REJECT" ] && echo "✓ default input: REJECT" || echo "✗ default input: $input (should be REJECT)"
[ "$forward" = "REJECT" ] && echo "✓ default forward: REJECT" || echo "✗ default forward: $forward (should be REJECT)"

# ===== ZONES =====
echo -e "\n[2/8] Firewall Zones"
echo "---"
uci show firewall | grep -q "zone.*name='lan'" && echo "✓ LAN zone exists" || echo "✗ LAN zone MISSING"
uci show firewall | grep -q "zone.*name='wan'" && echo "✓ WAN zone exists" || echo "✗ WAN zone MISSING"
uci show firewall | grep -q "zone.*name='vpn'" && echo "✓ VPN zone exists" || echo "✗ VPN zone MISSING"

wan_masq=$(uci show firewall | grep -E "zone.*wan" -A5 | grep "masq='1'" || true)
vpn_masq=$(uci show firewall | grep -E "zone.*vpn|vpn.*masq" | grep "masq='1'" || true)
[ -n "$wan_masq" ] && echo "✓ WAN masquerade: enabled" || echo "✗ WAN masquerade: MISSING"
[ -n "$vpn_masq" ] && echo "✓ VPN masquerade: enabled" || echo "✗ VPN masquerade: MISSING"

# ===== KILL SWITCH =====
echo -e "\n[3/8] Kill Switch (Critical)"
echo "---"
lan_vpn=$(uci show firewall | grep -E "forwarding.*lan.*vpn|forwarding.*src='lan'.*dest='vpn'" || true)
lan_wan=$(uci show firewall | grep -E "forwarding.*lan.*wan|forwarding.*src='lan'.*dest='wan'" || true)

[ -n "$lan_vpn" ] && echo "✓ LAN→VPN forwarding: enabled" || echo "✗ LAN→VPN forwarding: MISSING (no VPN routing!)"
[ -z "$lan_wan" ] && echo "✓ LAN→WAN forwarding: blocked (kill switch intact)" || echo "✗ LAN→WAN forwarding: EXISTS - KILL SWITCH BROKEN!"

# ===== DNS HIJACK PREVENTION =====
echo -e "\n[4/8] DNS Hijack Prevention"
echo "---"
dns_tcp=$(uci show firewall | grep -q "Block-External-DNS-TCP" && echo "found")
dns_udp=$(uci show firewall | grep -q "Block-External-DNS-UDP" && echo "found")

[ "$dns_tcp" = "found" ] && echo "✓ DNS hijack rule (TCP): present" || echo "⚠ DNS hijack rule (TCP): missing (optional but recommended)"
[ "$dns_udp" = "found" ] && echo "✓ DNS hijack rule (UDP): present" || echo "⚠ DNS hijack rule (UDP): missing (optional but recommended)"

# ===== DHCP CONFIGURATION =====
echo -e "\n[5/8] DHCP Configuration"
echo "---"
dhcp_enabled=$(uci get dhcp.lan.dhcpv4 2>/dev/null)
dhcp_dns=$(uci get dhcp.lan.dhcp_option 2>/dev/null)

[ "$dhcp_enabled" = "server" ] && echo "✓ DHCP server: enabled" || echo "✗ DHCP server: disabled or missing"
[ -n "$dhcp_dns" ] && echo "✓ DHCP DNS option: $dhcp_dns" || echo "⚠ DHCP DNS option: not set (clients may use external DNS)"

# ===== VPN TUNNEL =====
echo -e "\n[6/8] VPN Tunnel Status"
echo "---"
if ip link show awg0 2>/dev/null | grep -q UP; then
    echo "✓ VPN interface (awg0): UP"
    handshake=$(amneziawg show awg0 2>/dev/null | grep "latest handshake" || wg show awg0 2>/dev/null | grep "latest handshake")
    [ -n "$handshake" ] && echo "✓ $handshake" || echo "⚠ No recent handshake detected"
else
    echo "✗ VPN interface (awg0): DOWN or missing"
fi

# ===== WATCHDOG =====
echo -e "\n[7/8] Watchdog/Auto-Recovery"
echo "---"
/etc/init.d/awg-watchdog enabled 2>/dev/null && echo "✓ Watchdog auto-start: enabled" || echo "⚠ Watchdog auto-start: disabled"
pgrep -f "awg-watchdog" > /dev/null && echo "✓ Watchdog process: running" || echo "⚠ Watchdog process: not running"

# ===== IPv6 =====
echo -e "\n[8/8] IPv6 Status"
echo "---"
ipv6_disabled=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
[ "$ipv6_disabled" = "1" ] && echo "✓ IPv6: disabled (kernel)" || echo "⚠ IPv6: enabled at kernel level"

ipv6_forward=$(uci show firewall | grep -q "Block-IPv6-Forward" && echo "found")
[ "$ipv6_forward" = "found" ] && echo "✓ IPv6 forward blocking: enabled" || echo "⚠ IPv6 forward blocking: not configured"

echo -e "\n=========================================="
echo "AUDIT COMPLETE"
echo "=========================================="
echo "Fix any ✗ items before considering deployment complete."
echo "⚠ items are optional but recommended."
```

### 5.3 Live Traffic Tests

**Run from a CLIENT device (not the router) after cutover:**

```bash
# 1. Verify gateway
ip route | grep default
# Expected: default via [PRIVACY_ROUTER_IP]

# 2. Verify DNS server
cat /etc/resolv.conf
# Expected: nameserver [YOUR_DNS_IP]

# 3. Verify VPN exit
curl -s https://ipinfo.io
# Expected: VPN provider's IP and location

# 4. Verify ad blocking (if AdGuard/Pi-hole deployed)
nslookup doubleclick.net
# Expected: 0.0.0.0 or NXDOMAIN

# 5. Verify DNS hijack prevention
nslookup google.com 8.8.8.8
# Expected: timeout/failure (external DNS blocked)

# 6. Verify IPv6 blocked
curl -6 --connect-timeout 5 https://ipv6.icanhazip.com
# Expected: connection failed
```

### 5.4 Kill Switch Verification (Critical)

**This is the most important test. Traffic MUST NOT leak when VPN is down.**

```bash
# ON ROUTER: Bring down VPN
ip link set awg0 down

# ON CLIENT: Try to reach internet (should fail)
curl --connect-timeout 10 https://ipinfo.io/ip
# Expected: connection timeout - NO response

# If you get a response, YOUR IP IS LEAKING - kill switch is broken!
# Check: uci show firewall | grep forwarding
# There should be NO lan→wan forwarding

# ON ROUTER: Restore VPN
ip link set awg0 up

# ON CLIENT: Verify restored
curl https://ipinfo.io/ip
# Expected: VPN exit IP
```

---

## Mullvad-Specific Configuration Examples

### AmneziaWG Config for Mullvad

```ini
[Interface]
PrivateKey = YOUR_MULLVAD_PRIVATE_KEY

# Basic obfuscation (junk packets + header manipulation)
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

# QUIC protocol mimicry (recommended for DPI-heavy networks)
# Uncomment below to make traffic appear as QUIC/HTTP3
# I1 = <b 0xc70000000108ce1bf31eec7d93360000449e227e4596ed7f75c4d35ce31880b4...>
# (Full QUIC blob in openwrt/amneziawg/awg0.conf.example)

[Peer]
PublicKey = MULLVAD_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = MULLVAD_SERVER_IP:51820
PersistentKeepalive = 25
```

**Obfuscation Levels:**
| Level | Params | Use Case |
|-------|--------|----------|
| Basic | Jc, Jmin, Jmax, H1-H4 | Standard DPI bypass |
| QUIC Mimicry | + I1 (QUIC blob) | Traffic appears as HTTP/3 |
| Stealth | + Jc=16, aggressive junk | Maximum obfuscation |

See `scripts/awg-profiles.sh` for profile definitions and `openwrt/amneziawg/awg0.conf.example` for full QUIC I1 parameter.

### Mullvad Server Selection

Assume the user knows which server(s) they want. Server list: https://mullvad.net/en/servers

> **Failover note:** Same-city servers share one public key — simplifies multi-server failover config.

### Mullvad DNS Options

| DNS Server | URL | Features |
|------------|-----|----------|
| Standard | `https://dns.mullvad.net/dns-query` | Basic DNS |
| Ad-blocking | `https://adblock.dns.mullvad.net/dns-query` | Ads + trackers |
| Base | `https://base.dns.mullvad.net/dns-query` | Trackers only |
| Extended | `https://all.dns.mullvad.net/dns-query` | Ads + trackers + adult |
| Plain DNS | `100.64.0.4` | Inside VPN tunnel only |

---

## Knowledge Gaps

If you encounter unfamiliar scenarios, research these topics:

### VPN Provider Specific
- Search: `[provider name] wireguard config download`
- Search: `[provider name] amneziawg setup`
- Search: `[provider name] dns servers`

### Hardware Specific
- Search: `openwrt [device model] installation`
- Search: `[device] usb ethernet adapter openwrt`
- Search: `[hypervisor] openwrt vm setup bridged networking`

### Troubleshooting
- Search: `openwrt wireguard no internet`
- Search: `amneziawg handshake timeout`
- Search: `openwrt kill switch configuration`

### AmneziaWG Obfuscation
- If standard WireGuard is blocked, user needs AmneziaWG
- **Obfuscation is 100% client-side** — VPN providers (Mullvad, IVPN, Proton) use standard WireGuard servers
- Parameters from official [AmneziaWG documentation](https://amneziavpn.org/documentation/instructions/new-amneziawg-selfhosted)
- This repo includes working configs: `docker/config/awg0.conf.example`
- Reference: https://github.com/amnezia-vpn/amneziawg-tools

---

## Common Pitfalls & Agent Workarounds

**These are issues you will likely encounter. Plan for them.**

### 1. IP Address Conflict with Existing Router

**The Problem:** User's existing router is likely `192.168.1.1`. If you configure the privacy router to also be `192.168.1.1`, you'll have a conflict until cutover.

**Agent Strategy:**
```
BEFORE cutover:
  - Use a DIFFERENT IP for privacy router (e.g., 192.168.1.2)
  - This allows testing while existing router still works
  - SSH to 192.168.1.2 for configuration

AT cutover:
  - Existing router → AP mode (disable DHCP, assign static like 192.168.1.4)
  - Privacy router → Change to 192.168.1.1 (becomes new gateway)
  - OR: Keep privacy router at .2 and update DHCP to push .2 as gateway
```

**Commands:**
```bash
# During setup (before cutover), use different IP
uci set network.lan.ipaddr='192.168.1.2'
uci commit network
/etc/init.d/network restart

# AT cutover time, reclaim .1 if desired
uci set network.lan.ipaddr='192.168.1.1'
uci commit network
```

### 2. SSH Lockout During Firewall Changes

**The Problem:** Applying firewall rules can lock you out of SSH if rules are wrong.

**Agent Strategy:**
```bash
# ALWAYS use a revert timer before applying firewall changes
(sleep 120 && uci revert firewall && /etc/init.d/firewall restart) &

# Now apply changes
uci commit firewall
/etc/init.d/firewall restart

# If everything works, kill the revert timer
killall sleep

# If locked out, wait 2 minutes for automatic revert
```

### 3. Lost SSH After Network Interface Changes

**The Problem:** Changing network config while connected via SSH = disconnection.

**Agent Strategy:**
- Warn user: "You will lose SSH connection. Reconnect to new IP."
- Ensure user has physical/console access as backup
- If device has serial console or physical screen, prefer that during changes

```bash
# Before network changes, echo the plan
echo "After this change, reconnect via: ssh root@NEW_IP"

# Apply and immediately exit (don't wait for response)
uci commit network && /etc/init.d/network restart &
exit
```

### 4. VPN Handshake Fails - Routing Loop

**The Problem:** Default route via VPN before endpoint route exists = VPN packets try to go through VPN = infinite loop = no handshake.

**Detection:**
```bash
# Check if endpoint is routable via WAN (not via awg0!)
ip route get VPN_SERVER_IP
# WRONG: VPN_SERVER_IP dev awg0  ← routing loop!
# RIGHT: VPN_SERVER_IP via 192.168.1.1 dev eth0
```

**Fix:**
```bash
# Add explicit endpoint route via WAN gateway
ip route add VPN_SERVER_IP via WAN_GATEWAY

# Verify before setting default route
ip route get VPN_SERVER_IP
# Must show: via WAN_GATEWAY dev eth0

# NOW safe to set default route
ip route add default dev awg0
```

### 5. User's VPN Config Has Hostname, Not IP

**The Problem:** WireGuard Endpoint with hostname (e.g., `us-nyc-wg-001.relays.mullvad.net`) won't work reliably because DNS may not resolve during boot/reconnection.

**Agent Strategy:**
```bash
# Resolve hostname to IP during config generation
nslookup us-nyc-wg-001.relays.mullvad.net  # Example Mullvad hostname
# Or for other providers:
nslookup [your-provider-server].example.com

# Use the resolved IP in config, NOT the hostname
# awg0.conf:
Endpoint = 203.0.113.50:51820  # ✓ IP address (use actual resolved IP)
# NOT: Endpoint = server.vpnprovider.com:51820  # ✗ hostname
```

### 6. AmneziaWG Packages Not Found

**The Problem:** AmneziaWG isn't in standard OpenWrt repos. User needs to download from GitHub releases.

**Agent Strategy:**
```bash
# 1. Identify OpenWrt version and architecture
cat /etc/openwrt_release
uname -m

# 2. Download correct packages from:
# https://github.com/amnezia-vpn/amneziawg-openwrt/releases

# 3. Match version EXACTLY (e.g., 23.05.3 + aarch64_cortex-a72)

# 4. Install deps first
opkg update
opkg install kmod-crypto-lib-chacha20 kmod-crypto-lib-chacha20poly1305 \
             kmod-crypto-lib-curve25519 kmod-udptunnel4 kmod-udptunnel6

# 5. Install AWG packages
cd /tmp
wget [URL to kmod-amneziawg package]
wget [URL to amneziawg-tools package]
opkg install ./kmod-amneziawg_*.ipk
opkg install ./amneziawg-tools_*.ipk
```

### 7. DHCP Clients Keep Old DNS

**The Problem:** After changing DHCP to push new DNS (AdGuard), clients keep using old DNS until lease renewal.

**Agent Strategy:**
- Shorten DHCP lease time during transition
- Instruct user to manually renew on test device
- Or wait for natural lease expiry

```bash
# Temporarily shorten leases for faster rollout
uci set dhcp.lan.leasetime='5m'
uci commit dhcp
/etc/init.d/dnsmasq restart

# After all clients updated, restore normal lease time
uci set dhcp.lan.leasetime='12h'
uci commit dhcp
```

**Client-side renewal:**
```bash
# Linux
sudo dhclient -r && sudo dhclient

# Windows
ipconfig /release && ipconfig /renew

# macOS
sudo ipconfig set en0 BOOTP && sudo ipconfig set en0 DHCP
```

### 8. IPv6 Leaking Despite Being "Disabled"

**The Problem:** IPv6 can leak through multiple paths even after disabling in UCI.

**Agent Strategy - Defense in Depth:**
```bash
# Layer 1: UCI network config
uci set network.wan.ipv6='0'
uci set network.lan.ipv6='0'
uci delete network.wan6 2>/dev/null
uci commit network

# Layer 2: Kernel sysctl
echo 'net.ipv6.conf.all.disable_ipv6=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.default.disable_ipv6=1' >> /etc/sysctl.conf
sysctl -p

# Layer 3: Firewall (block any IPv6 that slips through)
ip6tables -P INPUT DROP 2>/dev/null
ip6tables -P OUTPUT DROP 2>/dev/null
ip6tables -P FORWARD DROP 2>/dev/null

# Layer 4: AdGuard (block AAAA records)
# In AdGuardHome.yaml: aaaa_disabled: true
```

### 9. Can't Determine WAN Gateway Automatically

**The Problem:** Scripts use `ip route | grep default` to find WAN gateway, but before VPN is up, there may be no default route.

**Agent Strategy:**
```bash
# Method 1: Get from DHCP lease
cat /tmp/dhcp.leases 2>/dev/null
uci get network.wan.gateway 2>/dev/null

# Method 2: Get from interface (if DHCP)
. /lib/functions/network.sh
network_get_gateway GATEWAY wan
echo $GATEWAY

# Method 3: Parse from WAN interface
ip route show dev eth0 | grep default | awk '{print $3}'

# Fallback: Ask user or use common default
echo "192.168.1.1"  # Common for most home networks
```

### 10. AdGuard Home Port 53 Conflict

**The Problem:** dnsmasq already binds to port 53. AdGuard can't start.

**Agent Strategy:**
```bash
# Option A: Disable dnsmasq DNS, keep DHCP
uci set dhcp.@dnsmasq[0].port='0'  # Disable DNS
uci commit dhcp
/etc/init.d/dnsmasq restart

# Option B: Run AdGuard on different port, redirect
# Run AdGuard on 5353, NAT redirect 53→5353
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port 5353
iptables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-port 5353
```

### 11. Kill Switch Test Shows False Positive

**The Problem:** Testing kill switch by bringing down `awg0` may show "working" but packets could be cached or using stale connections.

**Agent Strategy:**
```bash
# Proper kill switch test:
# 1. Clear connection tracking
conntrack -F

# 2. Bring down VPN
ip link set awg0 down

# 3. Wait for routing to update
sleep 2

# 4. Test with fresh connection (not cached)
curl --connect-timeout 5 https://ifconfig.me
# Should timeout or fail, NOT show any IP

# 5. Bring VPN back up
ip link set awg0 up
```

### 12. USB Ethernet Adapter Not Detected

**The Problem:** For single-NIC devices (Pi), USB Ethernet adapter may need drivers.

**Agent Strategy:**
```bash
# Check if adapter detected
lsusb
ip link show

# Common adapters need:
opkg update
opkg install kmod-usb-net-asix      # ASIX AX88xxx
opkg install kmod-usb-net-rtl8152   # Realtek RTL8152/8153
opkg install kmod-usb-net-cdc-ether # Generic CDC

# After install, replug adapter
# New interface should appear (often usb0 or eth1)
ip link show
```

---

## Error Recovery

### VPN Won't Connect

1. Verify endpoint IP is routable: `ping [VPN_SERVER_IP]`
2. Check keys match provider config
3. Verify obfuscation parameters (if AmneziaWG)
4. Try different VPN server/endpoint
5. Check firewall allows UDP to endpoint port

### Internet Works But VPN Bypass Possible

1. Check firewall zones: `uci show firewall | grep forwarding`
2. Ensure NO lan→wan forwarding exists
3. Verify default route: `ip route | grep default` should show awg0

### DNS Not Resolving

1. Check AdGuard running: `netstat -tlnp | grep 53`
2. Verify DHCP pushing correct DNS: `uci show dhcp`
3. Test upstream: `dig @[upstream_dns] google.com`

### Devices Not Getting New IP

1. Release/renew DHCP on client devices
2. Check DHCP server: `logread | grep dnsmasq`
3. Verify LAN interface up: `ip addr show br-lan`

### Kill Switch Not Working

1. Verify no lan→wan forwarding: `uci show firewall | grep -E "src='lan'.*dest='wan'"`
2. Check routing table: `ip route show`
3. Test with tunnel down: `ip link set awg0 down && curl google.com`

---

## Communication Style

When helping users:

1. **Explain the "why"** — Users should understand what each step accomplishes
2. **Verify before proceeding** — Confirm each step works before moving on
3. **Preserve connectivity** — Always ensure user can recover SSH access
4. **Backup configs** — Before major changes, save current state
5. **Test incrementally** — Don't make multiple changes at once

---

## Safety Rules

**NEVER:**
- Delete the only route to the management interface
- Apply firewall rules that lock out SSH without testing
- Modify WAN settings while connected via WAN
- Store private keys in logs or output

**ALWAYS:**
- Confirm user has console/physical access as backup
- Test firewall changes with timeout: `sleep 60 && uci revert firewall &`
- Keep a separate terminal with existing SSH session during changes
- Verify endpoint route exists before setting VPN as default route

---

## Quick Reference: Route Setup Order

**CRITICAL:** Route order matters. Wrong order = routing loop = no VPN connection.

```bash
# CORRECT ORDER:
# 1. Create interface
ip link add dev awg0 type amneziawg
amneziawg setconf awg0 /etc/amneziawg/awg0.conf
ip address add 10.x.x.x/32 dev awg0
ip link set up dev awg0

# 2. Add endpoint route FIRST (via WAN gateway)
ip route add VPN_SERVER_IP via WAN_GATEWAY

# 3. THEN set default route via VPN
ip route del default 2>/dev/null
ip route add default dev awg0
```

**Why this order:**
- Endpoint route ensures VPN handshake packets reach the server via WAN
- If default route via VPN comes first, handshake packets would go into VPN tunnel (which isn't up yet) → loop

---

## Research Escalation

**When to search online:** If you cannot resolve an issue from your knowledge base or this repository's documentation, use web search to find solutions. Don't guess or give up prematurely.

### Escalation Triggers

Search online when you encounter:

1. **Unfamiliar error messages** — Error text you haven't seen before
2. **Hardware-specific issues** — Device quirks, driver problems, firmware bugs
3. **Version-specific behavior** — OpenWrt version differences, package conflicts
4. **Provider-specific configuration** — VPN providers other than Mullvad
5. **Edge cases** — Unusual ISP setups, exotic network topologies
6. **Package availability** — Where to find packages for specific architectures

### Search Strategy

**Step 1: Construct targeted queries**

```
# Good queries (specific, include version/platform):
"OpenWrt 23.05 amneziawg kernel module not found"
"Raspberry Pi 5 USB ethernet adapter not detected OpenWrt"
"Mullvad WireGuard handshake timeout firewall"

# Poor queries (too vague):
"VPN not working"
"OpenWrt network problem"
```

**Step 2: Prioritize authoritative sources**

| Priority | Source | Why |
|----------|--------|-----|
| 1 | OpenWrt Forum / Wiki | Official, version-specific |
| 2 | GitHub Issues (amneziawg-openwrt, etc.) | Bug reports, workarounds |
| 3 | Reddit r/openwrt, r/WireGuard | Community solutions |
| 4 | VPN provider docs | Provider-specific config |
| 5 | Stack Exchange / ServerFault | General networking |

**Step 3: Validate before applying**

- Check publication date (networking changes fast)
- Verify applies to user's OpenWrt version
- Understand the change before executing
- Have rollback plan ready

### Deep Research Topics

For these complex topics, online research is **expected**:

| Topic | Search Focus |
|-------|--------------|
| AmneziaWG packages | GitHub releases for specific kernel version |
| OpenWrt on specific hardware | Device-specific wiki page, forum threads |
| ISP-specific issues (CGNAT, DS-Lite) | ISP name + WireGuard/VPN workarounds |
| Alternative VPN providers | Provider name + WireGuard + Linux setup |
| IPv6 tunnel brokers | If user needs IPv6 over IPv4-only VPN |
| Performance tuning | MTU optimization, WireGuard benchmarks |
| Kernel module compilation | Building packages for custom kernel |

### Research Tools

If your agent platform provides web search tools, use them:

```
# Example tool invocations (syntax varies by platform):

# Perplexity / Web Search
search("OpenWrt 23.05 kmod-amneziawg installation Raspberry Pi 5")

# Documentation lookup
search("site:openwrt.org WireGuard policy routing")

# GitHub-specific
search("site:github.com amneziawg-openwrt kernel 6.6")

# Forum search
search("site:forum.openwrt.org AmneziaWG handshake failed")
```

### When Research Fails

> **Upgrade your research tooling.** Native web search often fails for technical queries.
> Consider MCP servers with superior search capabilities (all pay-as-you-go with generous free tiers):
> - **[Jina](https://jina.ai/)** — Web search, page reading, reranking
> - **[Exa](https://exa.ai/)** — Semantic code search, API/SDK context
> - **[Ref](https://ref.tools/)** — Documentation search across frameworks/libraries
>
> These dramatically improve research quality for OpenWrt, WireGuard, and networking issues.

If upgraded research still doesn't yield a solution:

1. **Document what you tried** — List searches, sources consulted, approaches tested
2. **Identify the knowledge gap** — What specific information is missing?
3. **Suggest community resources** — Point user to OpenWrt forum, GitHub issues, Reddit
4. **Propose diagnostic steps** — What additional information would help?
5. **Consider alternative approaches** — Different VPN protocol, different hardware, etc.

---

*This document is designed for AI coding agents. Give your agent access to this entire repository for optimal results.*
