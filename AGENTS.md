# Agent Instructions: Privacy Router Deployment

You are assisting a user in deploying a network-wide VPN privacy router. This document provides your operational framework.

> **Development Note:** This stack was developed, tested, and deployed using **Claude Opus 4.5** via Claude Code with **Mullvad VPN**. The methodology below reflects lessons learned during that implementation.

## Your Mission

Help the user deploy a privacy router that:
1. Routes ALL network traffic through an encrypted VPN tunnel
2. Implements a hardware-level kill switch (no traffic leaks)
3. Provides DNS-level ad/tracker blocking
4. Automatically recovers from failures

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
□ Docker (on what host OS?)
□ Existing OpenWrt device
```

**Critical requirement:** The device needs TWO network interfaces (WAN + LAN). For single-NIC devices, a USB Ethernet adapter is required.

### 1.3 VPN Provider Details

**Recommended: Mullvad VPN** — This stack was developed and tested with Mullvad. They keep no customer records, require no personal info, and accept anonymous payment.

Obtain from user:

```
□ VPN provider name (Mullvad recommended, or IVPN, ProtonVPN, etc.)
□ WireGuard config file (download from provider's account page)
□ If using AmneziaWG obfuscation: parameters (Jc, Jmin, Jmax, S1, S2, H1-H4)
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
| **Optional Addons** | | |
| AdGuard Home (generic) | `adguard/AdGuardHome.yaml.example` | Any upstream DNS |
| **AdGuard Home (Mullvad)** | `adguard/mullvad-AdGuardHome.yaml.example` | Mullvad DoH |
| **Systemd service (AdGuard)** | `scripts/adguardhome.service` | Linux systemd |
| **BanIP config** | `openwrt/banip/banip.example` | Threat intelligence |
| **Docker** | | |
| Docker env (generic) | `docker/.env.example` | Any provider |
| **Docker env (Mullvad)** | `docker/mullvad.env.example` | Mullvad-optimized |

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

**For Mullvad users, use DoH to Mullvad DNS:**
```yaml
upstream_dns:
  - https://adblock.dns.mullvad.net/dns-query  # With ad blocking
  # OR
  - https://dns.mullvad.net/dns-query  # Without ad blocking
```

**Verification:**
```
□ AdGuard Home installed and running
□ Upstream DNS set to DoH (VPN provider)
□ DHCP pushing AdGuard IP to clients
□ DNS resolution working through AdGuard
□ Ad blocking verified (nslookup doubleclick.net → 0.0.0.0)
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

*This document is designed for AI coding agents. Give your agent access to this entire repository for optimal results.*
