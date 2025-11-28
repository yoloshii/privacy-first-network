# Optional Security Addons

The core privacy router provides VPN tunneling with a firewall-based kill switch. These optional addons enhance security and privacy but are **not required** for basic operation.

---

## Quick Reference

| Addon | Purpose | Recommended? |
|-------|---------|--------------|
| [AdGuard Home](#adguard-home) | DNS filtering, ad/tracker blocking | ✅ Highly recommended |
| [BanIP](#banip) | IP blocklist, threat intelligence | ✅ Recommended |
| [HTTPS for LuCI](#https-for-luci) | Encrypted admin interface | ⚠️ Optional |
| [Intrusion Detection](#intrusion-detection) | Deep packet inspection | ⚠️ Advanced users |

---

## AdGuard Home

**Purpose:** Network-wide ad blocking, tracker blocking, and DNS-over-HTTPS encryption.

**Why use it:**
- Blocks ads and trackers at DNS level (works for all devices)
- Encrypts DNS queries via DoH (ISP can't see your DNS lookups)
- Provides query logging and statistics
- Parental controls available

**Why skip it:**
- Adds complexity
- Requires additional resources (RAM/storage)
- VPN provider's DNS already provides basic protection

### Installation (OpenWrt)

```bash
# Download AdGuard Home
cd /tmp
wget https://static.adguard.com/adguardhome/release/AdGuardHome_linux_arm64.tar.gz
# Use linux_armv7 for Pi3, linux_amd64 for x86

tar xzf AdGuardHome_linux_arm64.tar.gz
mv AdGuardHome/AdGuardHome /usr/bin/
chmod +x /usr/bin/AdGuardHome

# Run initial setup
AdGuardHome -s install

# Access web UI at http://router-ip:3000
# Complete setup wizard
```

### Installation (Linux/systemd)

```bash
# Download and extract
curl -s -S -L https://static.adguard.com/adguardhome/release/AdGuardHome_linux_arm64.tar.gz | sudo tar xz -C /opt

# Copy systemd service
sudo cp scripts/adguardhome.service /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable adguardhome
sudo systemctl start adguardhome

# Access web UI at http://router-ip:3000
```

### Configuration

Use the example config as a starting point:

```bash
# For Mullvad users (recommended)
cp adguard/mullvad-AdGuardHome.yaml.example /opt/AdGuardHome/AdGuardHome.yaml

# For other VPN providers
cp adguard/AdGuardHome.yaml.example /opt/AdGuardHome/AdGuardHome.yaml
# Edit upstream_dns to your provider's DoH URL
```

**Key settings:**

| Setting | Mullvad Value | Purpose |
|---------|---------------|---------|
| `upstream_dns` | `https://adblock.dns.mullvad.net/dns-query` | Encrypted upstream |
| `enable_dnssec` | `true` | Validate DNS responses |
| `aaaa_disabled` | `true` | Block IPv6 (leak prevention) |

### Push AdGuard DNS to Clients

Configure DHCP to announce AdGuard as DNS server:

```bash
# On OpenWrt
uci add_list dhcp.lan.dhcp_option='6,ADGUARD_IP'
uci commit dhcp
/etc/init.d/dnsmasq restart

# Replace ADGUARD_IP with AdGuard's IP address
```

### Verification

```bash
# Test ad blocking
nslookup doubleclick.net
# Should return 0.0.0.0 or NXDOMAIN

# Check upstream is working
dig google.com @ADGUARD_IP
```

---

## BanIP

**Purpose:** Blocks malicious IPs using threat intelligence feeds (IP reputation lists).

**Why use it:**
- Blocks known malicious IPs before they reach your network
- Uses curated blocklists (Spamhaus, Emerging Threats, etc.)
- Automatic updates
- Low resource overhead

**Why skip it:**
- VPN already hides your real IP
- Primarily protects against inbound attacks (less relevant behind VPN)
- May block legitimate services if blocklists are too aggressive

### Installation (OpenWrt)

```bash
opkg update
opkg install banip

# Optional: Web UI
opkg install luci-app-banip
```

### Configuration

```bash
# Copy example config
cp openwrt/banip/banip.example /etc/config/banip

# IMPORTANT: Whitelist your VPN server IP
# Edit /etc/config/banip and add:
# list ban_allowlist 'YOUR_VPN_SERVER_IP/32'

# Enable and start
/etc/init.d/banip enable
/etc/init.d/banip start

# Check status
/etc/init.d/banip status
```

### Recommended Feeds

**Conservative (low false positives):**
```
drop        - Spamhaus DROP (worst of the worst)
edrop       - Spamhaus Extended DROP
feodo       - Banking trojan C2 servers
sslbl       - Malicious SSL certificates
```

**Moderate:**
```
etcompromised - Emerging Threats compromised IPs
dshield       - DShield top attackers
firehol1      - Firehol Level 1
```

**Aggressive (may cause false positives):**
```
firehol2    - Firehol Level 2
blocklist   - Blocklist.de reported IPs
tor         - Tor exit nodes (blocks Tor!)
```

### Verification

```bash
# Check loaded sets
/etc/init.d/banip status

# View blocked IPs
nft list set inet banip blocklist

# Check logs
logread | grep banip
```

### Troubleshooting

**VPN stops working after enabling BanIP:**
- Your VPN server IP was blocked
- Add to whitelist: `list ban_allowlist 'VPN_SERVER_IP/32'`
- Restart: `/etc/init.d/banip restart`

**High memory usage:**
- Reduce feeds or set `ban_maxelem` lower
- Disable aggressive feeds

---

## HTTPS for LuCI

**Purpose:** Encrypt OpenWrt admin interface.

**Why use it:**
- Prevents snooping on admin credentials
- Required if accessing router over untrusted network

**Why skip it:**
- LAN is already trusted (behind your firewall)
- Adds complexity with certificates
- Self-signed certs cause browser warnings

### Installation

```bash
opkg update
opkg install luci-ssl

# Force HTTPS redirect
uci set uhttpd.main.redirect_https='1'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

Access via `https://router-ip` (accept certificate warning).

---

## Intrusion Detection

**Purpose:** Deep packet inspection for malware/attack signatures.

**Why use it:**
- Detects malware, exploits, suspicious patterns
- Alerts on potential breaches

**Why skip it:**
- High resource usage (not suitable for low-power devices)
- Complex configuration
- VPN already encrypts traffic (IDS can't inspect)
- Better suited for enterprise networks

### Options

| Tool | Platform | Notes |
|------|----------|-------|
| Snort | OpenWrt (x86 only) | Heavy, needs 1GB+ RAM |
| Suricata | Linux | Production-grade IDS |
| Zeek | Linux | Network analysis framework |

**Recommendation:** Skip for most home users. VPN encryption makes IDS less effective anyway.

---

## Configuration Summary

### Minimal Setup (VPN only)
```
✅ AmneziaWG tunnel
✅ Kill switch (firewall zones)
✅ Watchdog (auto-recovery)
❌ AdGuard Home
❌ BanIP
```

### Recommended Setup
```
✅ AmneziaWG tunnel
✅ Kill switch (firewall zones)
✅ Watchdog (auto-recovery)
✅ AdGuard Home (DNS filtering + DoH)
✅ BanIP (threat intelligence)
```

### Maximum Security
```
✅ AmneziaWG tunnel
✅ Kill switch (firewall zones)
✅ Watchdog (auto-recovery)
✅ AdGuard Home (DNS filtering + DoH)
✅ BanIP (threat intelligence)
✅ HTTPS for LuCI
✅ SSH key-only auth
✅ Disable password login
```

---

## Resource Requirements

| Addon | RAM | Storage | CPU |
|-------|-----|---------|-----|
| AdGuard Home | ~50MB | ~100MB | Low |
| BanIP (6 feeds) | ~30MB | ~10MB | Low |
| BanIP (all feeds) | ~100MB | ~50MB | Medium |
| Snort/Suricata | 1GB+ | 500MB+ | High |

**Raspberry Pi 4/5:** Can run all recommended addons comfortably.

**Low-power devices:** Stick to minimal setup or AdGuard only.
