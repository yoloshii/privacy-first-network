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

### 1.2 Hardware for Privacy Router

Determine what the user will run OpenWrt on:

```
□ Dedicated hardware (Raspberry Pi 4/5, x86 mini PC)
□ Virtual machine (which hypervisor?)
□ Existing OpenWrt device
```

**Critical requirement:** The device needs TWO network interfaces (WAN + LAN). For single-NIC devices, a USB Ethernet adapter is required.

### 1.3 VPN Provider Details

**Deep research the user's VPN provider** to determine:
- Does it support WireGuard? (required)
- Does it provide AmneziaWG obfuscation parameters? (optional, for DPI bypass)
- What are the provider's DNS servers?

```
Search: "[provider name] wireguard config linux"
Search: "[provider name] amneziawg parameters"
```

**If user hasn't chosen a provider yet:** Recommend Mullvad (see README for rationale).

**If user is in a high-censorship region:** WireGuard/AmneziaWG may be insufficient. Deep research current obfuscation methods:

```
Search: "best VPN obfuscation protocol 2025"
Search: "VLESS Reality XRay setup guide"
```

> This stack focuses on WireGuard/AmneziaWG. For advanced protocols (VLESS, XRay), research dedicated solutions.

Obtain from user:

```
□ VPN provider name (strongly recommend Mullvad)
□ WireGuard config file (download from provider's account page)
□ If using AmneziaWG obfuscation: parameters (Jc, Jmin, Jmax, S1, S2, H1-H4)
  - Use example AWG params from this repo (work with any WireGuard server)
  - For self-hosted: Amnezia server generates params automatically
□ Assigned internal VPN IP (e.g., 10.66.x.x/32 for Mullvad)
□ VPN server endpoint IP and port
□ Private key and server public key
```

**For Mullvad users:**
- Get WireGuard config: https://mullvad.net/en/account/wireguard-config
- Server list with IPs: https://mullvad.net/en/servers
- DNS servers: `100.64.0.4` (plain) or `https://adblock.dns.mullvad.net/dns-query` (DoH with blocking)

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
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Step-by-step installation procedures |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Config file syntax and options |
| [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | Deep technical understanding |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | When things go wrong |

### Implementation Templates

Use these example configs, substituting user-specific values:

| Template | Location | Notes |
|----------|----------|-------|
| **Core (Required)** | | |
| Network interfaces | `openwrt/network/interfaces.example` | Generic OpenWrt |
| Firewall zones | `openwrt/firewall/zones.example` | Kill switch architecture |
| DHCP config | `openwrt/dhcp/dhcp.example` | DNS push to clients |
| VPN tunnel (generic) | `openwrt/amneziawg/awg0.conf.example` | Any WireGuard provider |
| **VPN tunnel (Mullvad)** | `openwrt/amneziawg/mullvad-awg0.conf.example` | Mullvad-optimized |
| Watchdog script | `scripts/awg-watchdog.sh` | Auto-recovery daemon |
| Hotplug script | `scripts/99-awg-hotplug` | WAN-up trigger |
| **Init script (OpenWrt)** | `scripts/awg-watchdog.init` | Boot persistence |
| **Systemd service (AWG)** | `scripts/awg-watchdog.service` | Linux systemd |
| **Optional Addons (ask user in 1.5)** | | |
| AdGuard Home (generic) | `adguard/AdGuardHome.yaml.example` | Any upstream DNS |
| AdGuard Home (Mullvad) | `adguard/mullvad-AdGuardHome.yaml.example` | Mullvad DoH |
| Systemd service (AdGuard) | `scripts/adguardhome.service` | Linux systemd |
| BanIP config | `openwrt/banip/banip.example` | Threat intelligence |

---

## Phase 4: Execution Checklist

Guide the user through these steps, verifying each before proceeding:

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
□ Manual tunnel test successful
□ VPN exit IP confirmed
```

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
uci set dhcp.@dnsmasq[0].server='100.64.0.4'  # Mullvad DNS
uci commit dhcp
/etc/init.d/dnsmasq restart
```

Verification (without AdGuard):
```
□ DNS resolves through VPN tunnel
□ nslookup google.com returns result
□ DNS not leaking (test at dnsleaktest.com through VPN)
```

### 4.5 Reliability

```
□ Watchdog script installed and running
□ Hotplug script installed for WAN reconnection
□ Boot persistence configured
□ IPv6 disabled at all levels
```

### 4.6 Cutover

```
□ Existing router set to AP/bridge mode
□ Cables connected: Modem → Privacy Router → WiFi AP
□ All devices receiving new DHCP leases
□ Full connectivity test from multiple devices
```

---

## Phase 5: Validation Tests

After deployment, run these verification tests:

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

---

## Mullvad-Specific Configuration Examples

### AmneziaWG Config for Mullvad

```ini
[Interface]
PrivateKey = YOUR_MULLVAD_PRIVATE_KEY

# Obfuscation parameters (Mullvad uses standard WireGuard)
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = MULLVAD_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = MULLVAD_SERVER_IP:51820
PersistentKeepalive = 25
```

### Mullvad Server Selection

Choose a server close to user's location from https://mullvad.net/en/servers

Common endpoints (verify current IPs):
- `au-mel-wg-001` - Melbourne, Australia
- `au-syd-wg-001` - Sydney, Australia
- `us-nyc-wg-001` - New York, USA
- `us-lax-wg-001` - Los Angeles, USA
- `gb-lon-wg-001` - London, UK
- `de-fra-wg-001` - Frankfurt, Germany
- `sg-sin-wg-001` - Singapore
- `jp-tyo-wg-001` - Tokyo, Japan

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
- Obfuscation parameters come from VPN provider or Amnezia VPN app
- Reference: https://github.com/amnezia-vpn/amneziawg-tools

---

## Common Pitfalls & Agent Workarounds

**These are issues you WILL encounter. Plan for them.**

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
nslookup us-nyc-wg-001.relays.mullvad.net

# Use the IP in config, NOT the hostname
# awg0.conf:
Endpoint = 185.213.154.68:51820  # ✓ IP address
# NOT: Endpoint = us-nyc-wg-001.relays.mullvad.net:51820  # ✗ hostname
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

If online research doesn't yield a solution:

1. **Document what you tried** — List searches, sources consulted, approaches tested
2. **Identify the knowledge gap** — What specific information is missing?
3. **Suggest community resources** — Point user to OpenWrt forum, GitHub issues, Reddit
4. **Propose diagnostic steps** — What additional information would help?
5. **Consider alternative approaches** — Different VPN protocol, different hardware, etc.

**Example response when stuck:**

```
I've searched for solutions to [specific issue] but haven't found a definitive answer.

Sources consulted:
- OpenWrt forum: [relevant threads found/not found]
- GitHub issues: [related issues]
- Reddit: [community experiences]

The issue appears to be [your best assessment].

Recommended next steps:
1. [Specific diagnostic command]
2. [Alternative approach to try]
3. Post to OpenWrt forum with [these details] if unresolved

Would you like me to help draft a forum post, or try [alternative approach]?
```

---

*This document is designed for AI coding agents. Give your agent access to this entire repository for optimal results.*
