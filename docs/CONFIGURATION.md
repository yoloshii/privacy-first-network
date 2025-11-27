# Configuration Reference

Complete reference for all configuration files and options.

## Table of Contents

1. [AmneziaWG Configuration](#amneziawg-configuration)
2. [OpenWrt Network Configuration](#openwrt-network-configuration)
3. [OpenWrt Firewall Configuration](#openwrt-firewall-configuration)
4. [OpenWrt DHCP Configuration](#openwrt-dhcp-configuration)
5. [AdGuard Home Configuration](#adguard-home-configuration)
6. [Watchdog Script Configuration](#watchdog-script-configuration)
7. [Environment Variables](#environment-variables)

---

## AmneziaWG Configuration

**File:** `/etc/amneziawg/awg0.conf`

```ini
[Interface]
# Your WireGuard private key (base64)
# Generate with: amneziawg genkey
PrivateKey = YOUR_PRIVATE_KEY

# AmneziaWG Obfuscation Parameters
# These MUST match your VPN server configuration

# Jc: Number of junk packets to send during handshake
# Higher = more obfuscation, more overhead
# Range: 1-128, Recommended: 3-8
Jc = 4

# Jmin/Jmax: Min/max size of junk packets in bytes
# Larger range = harder to fingerprint
# Range: 0-1280
Jmin = 40
Jmax = 70

# S1/S2: Init packet magic header manipulation
# Range: 0-2147483647
S1 = 0
S2 = 0

# H1-H4: Header field obfuscation
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

### Provider-Specific Notes

**Mullvad:**
- Download WireGuard config from account page
- Mullvad doesn't officially support AmneziaWG
- Use standard WireGuard values and add AWG parameters
- AWG parameters must be set to match (usually defaults)

**IVPN:**
- Similar to Mullvad - add AWG parameters to standard config

**Self-hosted:**
- Configure matching AWG parameters on server

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
    # Router's own DNS (VPN provider's DNS)
    option dns '100.64.0.4'
```

| Option | Description | Example |
|--------|-------------|---------|
| `device` | Bridge device name | `br-lan` |
| `proto` | Protocol (static/dhcp) | `static` |
| `ipaddr` | Gateway IP address | `192.168.1.1` |
| `netmask` | Subnet mask | `255.255.255.0` |
| `dns` | DNS servers for router | `100.64.0.4` |

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
```

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

## Environment Variables

For Docker deployment, create `.env` file:

```bash
# VPN Configuration
VPN_PRIVATE_KEY=your_private_key_base64
VPN_SERVER_PUBLIC_KEY=server_public_key_base64
VPN_SERVER_ENDPOINT=vpn.example.com:51820
VPN_INTERNAL_IP=10.x.x.x

# AmneziaWG Obfuscation
AWG_JC=4
AWG_JMIN=40
AWG_JMAX=70
AWG_S1=0
AWG_S2=0
AWG_H1=1
AWG_H2=2
AWG_H3=3
AWG_H4=4

# Network Configuration
LAN_SUBNET=192.168.1.0/24
LAN_GATEWAY=192.168.1.1
DNS_SERVER=192.168.1.5

# AdGuard Configuration
ADGUARD_PORT=3000
ADGUARD_DNS_PORT=53
ADGUARD_UPSTREAM=https://adblock.dns.mullvad.net/dns-query
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
