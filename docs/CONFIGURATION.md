# Configuration Reference

Complete reference for all configuration files and options.

## Table of Contents

1. [AmneziaWG Configuration](#amneziawg-configuration)
2. [OpenWrt Network Configuration](#openwrt-network-configuration)
3. [OpenWrt Firewall Configuration](#openwrt-firewall-configuration)
4. [VPN Bypass Routing](#vpn-bypass-routing)
5. [OpenWrt DHCP Configuration](#openwrt-dhcp-configuration)
6. [AdGuard Home Configuration](#adguard-home-configuration)
7. [Watchdog Script Configuration](#watchdog-script-configuration)
8. [Environment Variables](#environment-variables)

---

## AmneziaWG Configuration

**File:** `/etc/amneziawg/awg0.conf`

```ini
[Interface]
# Your WireGuard private key (base64)
# Generate with: amneziawg genkey
PrivateKey = YOUR_PRIVATE_KEY

# AmneziaWG Obfuscation Parameters
# These add CLIENT-SIDE obfuscation to disguise WireGuard traffic.
# The obfuscation happens LOCALLY - servers don't need AmneziaWG support.
#
# IMPORTANT: Most VPN providers (Mullvad, IVPN, Proton, etc.) do NOT provide
# AmneziaWG parameters because they use standard WireGuard servers.
#
# The defaults below are WORKING VALUES compatible with ANY standard WireGuard
# server. Source: wgtunnel's AmneziaWG compatibility mode.
# https://github.com/zaneschepke/wgtunnel

# Jc: Number of junk packets to send during handshake
# Higher = more obfuscation, more overhead
# Range: 1-128, Default: 4
Jc = 4

# Jmin/Jmax: Min/max size of junk packets in bytes
# Larger range = harder to fingerprint
# Range: 0-1280
Jmin = 40
Jmax = 70

# S1/S2: Init packet magic header manipulation
# Set to 0 for standard WireGuard compatibility
# Range: 0-2147483647
S1 = 0
S2 = 0

# H1-H4: Header field obfuscation
# Sequential values (1,2,3,4) for standard WireGuard compatibility
# Range: 0-2147483647
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
# VPN server's public key (from your provider)
PublicKey = SERVER_PUBLIC_KEY

# Optional: Pre-shared key for post-quantum security
# PresharedKey = PRESHARED_KEY

# Route all traffic through VPN
AllowedIPs = 0.0.0.0/0, ::/0

# VPN server address
Endpoint = vpn.example.com:51820

# Keep connection alive (important for NAT traversal)
# Sends keepalive every N seconds
PersistentKeepalive = 25
```

### Generating Keys

```bash
# Generate private key
amneziawg genkey > privatekey

# Generate public key from private key
amneziawg pubkey < privatekey > publickey

# Generate preshared key (optional)
amneziawg genpsk > presharedkey
```

### Obfuscation Profiles (AmneziaWG 1.5)

The `awg-profiles.sh` library provides pre-configured obfuscation profiles that inject protocol-signature packets for DPI evasion:

| Profile | Mimics | DPI Resistance | Parameters Added |
|---------|--------|----------------|------------------|
| `basic` | None | Medium | Base Jc/H1-H4 only |
| `quic` | HTTP/3 | High | i1 (QUIC Initial), i2, j1, itime |
| `dns` | DNS query | Medium | i1 (DNS query), itime |
| `sip` | VoIP | Medium | i1 (SIP INVITE), i2, j1, itime |
| `stealth` | HTTP/3 | Maximum | QUIC + Jc=16, Jmin=100, Jmax=200 |

**Installation:**
```bash
# OpenWrt
cp scripts/awg-profiles.sh /etc/amneziawg/awg-profiles.sh

# Docker (included automatically)
```

**Configuration:**
```bash
# In watchdog or hotplug scripts
AWG_PROFILE="quic"

# In Docker .env
AWG_PROFILE=quic
```

All profiles work with standard WireGuard servers (Mullvad, IVPN, Proton).

### Provider-Specific Notes

**Understanding AmneziaWG with Standard VPN Providers:**

AmneziaWG obfuscation is **client-side only**. The client adds junk packets and header modifications before sending, and the server receives valid WireGuard packets. This means:

- **Any standard WireGuard server works** - no special server support needed
- **VPN providers don't provide AWG parameters** - because their servers are standard WireGuard
- **Use the default values in this repo** - they're tested with Mullvad, IVPN, and other providers

**Mullvad / IVPN / Proton / Others:**
1. Download WireGuard config from your provider's account page
2. Copy `PrivateKey` and `PublicKey` values to your awg0.conf
3. Keep the default AWG obfuscation parameters (Jc, Jmin, Jmax, S1, S2, H1-H4)
4. These defaults work with all standard WireGuard servers

**Self-hosted AmneziaWG:**
- If running your own AmneziaWG server, configure matching parameters on both sides
- For standard WireGuard server, use the defaults in this repo

---

## OpenWrt Network Configuration

**File:** `/etc/config/network` (UCI format)

### LAN Interface

```
config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'
    option ip6assign '60'
    # Router's own DNS (use your VPN provider's DNS)
    # Mullvad options:
    #   10.64.0.1   - Standard (no blocking)
    #   100.64.0.1  - Ad-blocking
    #   100.64.0.2  - Ad + Tracker blocking
    #   100.64.0.3  - Ad + Tracker + Malware
    #   100.64.0.4  - Ad + Tracker + Malware + Adult (recommended)
    # IVPN: 10.0.254.1 | Proton: 10.2.0.1
    option dns 'VPN_PROVIDER_DNS_IP'
```

| Option | Description | Example |
|--------|-------------|---------|
| `device` | Bridge device name | `br-lan` |
| `proto` | Protocol (static/dhcp) | `static` |
| `ipaddr` | Gateway IP address | `192.168.1.1` |
| `netmask` | Subnet mask | `255.255.255.0` |
| `dns` | DNS servers for router | Provider DNS IP |

### WAN Interface

```
config interface 'wan'
    option device 'eth0'
    option proto 'dhcp'
    # Disable IPv6 to prevent leaks
    option ipv6 '0'
```

| Option | Description | Example |
|--------|-------------|---------|
| `device` | WAN interface name | `eth0` |
| `proto` | Protocol (dhcp/static/pppoe) | `dhcp` |
| `ipv6` | Enable/disable IPv6 | `0` (disabled) |

### Bridge Configuration

```
config device
    option name 'br-lan'
    option type 'bridge'
    list ports 'eth1'
```

### UCI Commands

```bash
# View current config
uci show network

# Set value
uci set network.lan.ipaddr='192.168.1.1'

# Commit changes
uci commit network

# Restart networking
/etc/init.d/network restart
```

---

## OpenWrt Firewall Configuration

**File:** `/etc/config/firewall` (UCI format)

### Default Policies

```
config defaults
    option syn_flood '1'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option drop_invalid '1'
```

> **Edge hardening:** `drop_invalid` drops malformed packets that don't match any known connection state. Essential when router is the network edge (not behind another firewall).

### LAN Zone

```
config zone
    option name 'lan'
    option network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'
```

### WAN Zone

```
config zone
    option name 'wan'
    list network 'wan'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option masq '1'
    option mtu_fix '1'
```

### VPN Zone (Kill Switch Core)

```
config zone
    option name 'vpn'
    option device 'awg0'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option masq '1'
    option mtu_fix '1'
```

### Forwarding Rules

```
# LAN to VPN - ALLOWED (this is the only path to internet)
config forwarding
    option src 'lan'
    option dest 'vpn'

# Note: NO lan->wan forwarding = kill switch
# If VPN is down, traffic has nowhere to go
```

### Zone Reference

| Zone | Input | Output | Forward | Masquerade | Purpose |
|------|-------|--------|---------|------------|---------|
| lan | ACCEPT | ACCEPT | ACCEPT | No | Local management |
| wan | REJECT | ACCEPT | REJECT | Yes | ISP connection |
| vpn | REJECT | ACCEPT | REJECT | Yes | VPN tunnel |

### Forwarding Reference

| Source | Destination | Allowed | Purpose |
|--------|-------------|---------|---------|
| lan | vpn | Yes | Internet via VPN |
| lan | wan | **No** | Kill switch |
| vpn | wan | No | N/A |

### DNS Hijack Prevention (Recommended)

Blocks devices from bypassing your DNS server with hardcoded addresses (e.g., 8.8.8.8):

```
config rule
    option name 'Block-External-DNS-TCP'
    option src 'lan'
    option dest 'vpn'
    option dest_port '53'
    option proto 'tcp'
    option target 'REJECT'
    option family 'ipv4'
    option src_ip '!192.168.1.5'    # Except your AdGuard/DNS server

config rule
    option name 'Block-External-DNS-UDP'
    option src 'lan'
    option dest 'vpn'
    option dest_port '53'
    option proto 'udp'
    option target 'REJECT'
    option family 'ipv4'
    option src_ip '!192.168.1.5'    # Except your AdGuard/DNS server
```

UCI commands:
```bash
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

---

## VPN Bypass Routing

Allows specific devices to bypass the VPN and access the internet directly via WAN.

### Why Bypass is Needed

Some devices need direct WAN access:
- **Infrastructure hosts** (hypervisor, DNS server) - require uninterrupted updates
- **Proxmox/ESXi nodes** - cluster communication, backup uploads
- **Developer workstations** - geo-specific services, corporate VPNs
- **Specific use cases** - local streaming, banking apps that block VPNs

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Traffic Flow                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  LAN Device                                                 │
│      │                                                      │
│      ▼                                                      │
│  ┌──────────────────┐                                       │
│  │  Policy Routing  │                                       │
│  │   ip rule show   │                                       │
│  └────────┬─────────┘                                       │
│           │                                                 │
│     ┌─────┴─────┐                                           │
│     │           │                                           │
│     ▼           ▼                                           │
│ "from X.X.X.X"  All others                                  │
│ lookup 100      lookup main                                 │
│     │               │                                       │
│     ▼               ▼                                       │
│ ┌─────────┐    ┌─────────┐                                  │
│ │ Table   │    │  Main   │                                  │
│ │   100   │    │  Table  │                                  │
│ │         │    │         │                                  │
│ │ default │    │ 0/1     │                                  │
│ │ via WAN │    │ 128/1   │                                  │
│ └────┬────┘    │ via awg0│                                  │
│      │         └────┬────┘                                  │
│      ▼              ▼                                       │
│   ┌─────┐      ┌─────────┐                                  │
│   │ WAN │      │  awg0   │                                  │
│   │eth0 │      │  (VPN)  │                                  │
│   └──┬──┘      └────┬────┘                                  │
│      │              │                                       │
│      ▼              ▼                                       │
│    ISP           Mullvad                                    │
│  (direct)       (encrypted)                                 │
└─────────────────────────────────────────────────────────────┘
```

### Components Required

1. **Routing Table 100** - Contains only WAN default route (created by hotplug)
2. **Policy Rules** - Direct specific IPs to use table 100 (in `/etc/rc.local`)
3. **Firewall Rules** - Allow lan→wan for bypass devices (in `/etc/config/firewall`)

### Step 1: Verify Table 100 Exists

The 99-awg hotplug script creates table 100 automatically:

```bash
# Check table 100 has WAN route
ip route show table 100
# Expected: default via <WAN_GW> dev eth0

# Check main table has VPN split routes
ip route show | grep -E "^(0\.0\.0\.0/1|128\.0\.0\.0/1)"
# Expected:
# 0.0.0.0/1 dev awg0
# 128.0.0.0/1 dev awg0
```

### Step 2: Add Policy Rules

**File:** `/etc/rc.local` (before `exit 0`)

```bash
# =============================================================================
# VPN Bypass Policy Rules
# =============================================================================
# Syntax: ip rule add from <IP> lookup 100 priority 100
# Each IP here uses table 100 (WAN only) instead of main table (VPN)

# Infrastructure (RECOMMENDED)
ip rule add from 192.168.1.3 lookup 100 priority 100   # Hypervisor
ip rule add from 192.168.1.5 lookup 100 priority 100   # DNS Server

# Proxmox/Virtualization nodes
ip rule add from 192.168.1.10 lookup 100 priority 100  # Node 1
ip rule add from 192.168.1.11 lookup 100 priority 100  # Node 2

# Workstations/Servers
ip rule add from 192.168.1.20 lookup 100 priority 100  # Workstation
ip rule add from 192.168.1.100 lookup 100 priority 100 # Server LXC

exit 0
```

Apply immediately:
```bash
/etc/rc.local
```

Verify:
```bash
ip rule show | grep "lookup 100"
```

### Step 3: Add Firewall Rules

**File:** `/etc/config/firewall`

Each bypass device needs a firewall rule allowing lan→wan:

```
# With MAC binding (recommended for physical devices)
config rule
    option name 'Bypass-Workstation'
    option src 'lan'
    option src_ip '192.168.1.20'
    option src_mac 'XX:XX:XX:XX:XX:XX'
    option dest 'wan'
    option target 'ACCEPT'

# IP-only (for VMs/containers where MAC may change)
config rule
    option name 'Bypass-Server-LXC'
    option src 'lan'
    option src_ip '192.168.1.100'
    option dest 'wan'
    option target 'ACCEPT'
```

UCI commands:
```bash
# Add rule
uci add firewall rule
uci set firewall.@rule[-1].name='Bypass-Workstation'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].src_ip='192.168.1.20'
uci set firewall.@rule[-1].src_mac='XX:XX:XX:XX:XX:XX'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
/etc/init.d/firewall restart
```

### Verification

```bash
# 1. Check policy rules are active
ip rule show | grep 100
# Should list your bypass rules

# 2. Check table 100 routing
ip route show table 100
# Should show: default via <WAN_GW> dev eth0

# 3. From bypass device, check you're NOT on VPN
curl -s https://am.i.mullvad.net/connected
# Should return: "You are not connected to Mullvad"

# 4. From VPN device, verify VPN works
curl -s https://am.i.mullvad.net/connected
# Should return Mullvad connection info
```

### Important Notes

1. **Both rules required**: Policy rule (ip rule) routes traffic to table 100, firewall rule allows the forwarding.

2. **DNS consideration**: Bypass devices should use external DNS (not AdGuard) or AdGuard itself needs bypass.

3. **Kill switch preserved**: The kill switch (no lan→wan forwarding) remains active for all non-bypass devices.

4. **MAC binding optional**: For containers/VMs use IP-only rules. For physical devices, MAC+IP prevents spoofing.

5. **Order matters**: Policy rules are checked in priority order (lower = higher priority).

---

## OpenWrt DHCP Configuration

**File:** `/etc/config/dhcp` (UCI format)

### DNSmasq Settings

```
config dnsmasq
    option domainneeded '1'
    option boguspriv '1'
    option localise_queries '1'
    option rebind_protection '1'
    option local '/lan/'
    option domain 'lan'
    option expandhosts '1'
    option authoritative '1'
    option readethers '1'
    option leasefile '/tmp/dhcp.leases'
    option cachesize '1000'
```

### LAN DHCP Pool

```
config dhcp 'lan'
    option interface 'lan'
    option start '100'
    option limit '150'
    option leasetime '12h'
    option dhcpv4 'server'
    # Push AdGuard Home as DNS server
    list dhcp_option '6,192.168.1.5'
```

| Option | Description | Example |
|--------|-------------|---------|
| `start` | First DHCP address (offset from network) | `100` (192.168.1.100) |
| `limit` | Number of addresses | `150` |
| `leasetime` | Lease duration | `12h` |
| `dhcp_option` | DHCP options to send | `6,IP` (option 6 = DNS) |

### DHCP Option Reference

| Option | Code | Purpose | Example |
|--------|------|---------|---------|
| DNS | 6 | DNS servers | `6,192.168.1.5` |
| Gateway | 3 | Default gateway | `3,192.168.1.1` |
| NTP | 42 | Time server | `42,192.168.1.1` |
| Domain | 15 | Domain name | `15,home.lan` |

---

## AdGuard Home Configuration

**File:** `/opt/AdGuardHome/AdGuardHome.yaml`

### DNS Settings

```yaml
dns:
  # Listen address
  bind_hosts:
    - 0.0.0.0
  port: 53

  # Upstream DNS servers (DNS-over-HTTPS recommended)
  upstream_dns:
    - https://adblock.dns.mullvad.net/dns-query
    # Alternative: Cloudflare
    # - https://cloudflare-dns.com/dns-query
    # Alternative: Quad9
    # - https://dns.quad9.net/dns-query

  # Bootstrap DNS (for resolving upstream hostnames)
  bootstrap_dns:
    - 9.9.9.9
    - 1.1.1.1

  # Enable DNSSEC validation
  enable_dnssec: true

  # Cache settings
  cache_size: 4194304  # 4MB
  cache_ttl_min: 300
  cache_ttl_max: 86400

  # Performance
  all_servers: false  # Query upstreams in sequence
  fastest_addr: false
  parallel_requests: true
```

### Filtering Settings

```yaml
filtering:
  # Enable filtering
  filtering_enabled: true

  # Safe search (optional)
  safe_search:
    enabled: false

  # Parental control (optional)
  parental:
    enabled: false

  # Blocking mode
  # null_ip: Return 0.0.0.0
  # refused: Return REFUSED
  # nxdomain: Return NXDOMAIN
  blocking_mode: null_ip

  # Block IPv6 AAAA queries (leak prevention)
  aaaa_disabled: true
```

### Filter Lists

```yaml
filters:
  - enabled: true
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard DNS filter
    id: 1

  - enabled: true
    url: https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
    name: StevenBlack Hosts
    id: 2

  - enabled: true
    url: https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext
    name: Peter Lowe's List
    id: 3
```

### Web Interface

```yaml
http:
  address: 0.0.0.0:3000
  session_ttl: 720h

users:
  - name: admin
    password: $2a$10$...  # bcrypt hash
```

---

## Watchdog Script Configuration

**File:** `/etc/awg-watchdog.sh`

### Configuration Variables

```bash
# Path to AmneziaWG config
CONFIG_FILE="/etc/amneziawg/awg0.conf"

# Log file location
LOG_FILE="/var/log/awg-watchdog.log"

# Seconds between connectivity checks
CHECK_INTERVAL=30

# Number of failures before restart
FAIL_THRESHOLD=3

# IPs to ping for connectivity test
# Use reliable, geo-distributed targets
PROBE_TARGETS="1.1.1.1 8.8.8.8"

# Your VPN internal IP (from VPN provider)
VPN_IP="10.x.x.x"

# VPN server endpoint IP
ENDPOINT_IP="vpn.server.ip"

# Gateway for endpoint route (usually WAN gateway)
# Set to your modem's IP or use auto-detection
LAN_GATEWAY="192.168.1.1"
```

### Timing Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CHECK_INTERVAL` | 30 | Seconds between checks |
| `FAIL_THRESHOLD` | 3 | Failures before restart |
| Total detection time | 90s | CHECK_INTERVAL × FAIL_THRESHOLD |

### Log Rotation

Add to cron (`/etc/crontabs/root`):

```
# Rotate watchdog log daily at 4am, keep 7 days
0 4 * * * /usr/bin/find /var/log -name 'awg-watchdog.log.*' -mtime +7 -delete; /bin/mv /var/log/awg-watchdog.log /var/log/awg-watchdog.log.$(date +\%Y\%m\%d)
```

---

## Quick Reference

### Essential Files

| File | Purpose |
|------|---------|
| `/etc/amneziawg/awg0.conf` | VPN tunnel configuration |
| `/etc/config/network` | Network interfaces |
| `/etc/config/firewall` | Firewall zones and rules |
| `/etc/config/dhcp` | DHCP server settings |
| `/etc/awg-watchdog.sh` | Tunnel health monitor |
| `/etc/hotplug.d/iface/99-awg` | Auto-start on WAN up |

### Important Paths

| Path | Purpose |
|------|---------|
| `/var/log/awg-watchdog.log` | Watchdog log |
| `/tmp/dhcp.leases` | DHCP lease database |
| `/etc/crontabs/root` | Scheduled tasks |
| `/opt/AdGuardHome/` | AdGuard installation |

### UCI Quick Commands

```bash
# Network
uci show network
uci set network.lan.ipaddr='192.168.1.1'
uci commit network
/etc/init.d/network restart

# Firewall
uci show firewall
uci commit firewall
/etc/init.d/firewall restart

# DHCP
uci show dhcp
uci commit dhcp
/etc/init.d/dnsmasq restart
```
