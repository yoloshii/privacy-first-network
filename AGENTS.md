# Agent Instructions: Privacy Router Deployment

You are assisting a user in deploying a network-wide VPN privacy router. This document provides your operational framework.

## Your Mission

Help the user deploy a privacy router that:
1. Routes ALL network traffic through an encrypted VPN tunnel
2. Implements a hardware-level kill switch (no traffic leaks)
3. Provides DNS-level ad/tracker blocking
4. Automatically recovers from failures

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

Obtain from user:

```
□ VPN provider name (Mullvad, IVPN, ProtonVPN, etc.)
□ WireGuard or AmneziaWG config file
□ If AmneziaWG: obfuscation parameters (Jc, Jmin, Jmax, S1, S2, H1-H4)
□ Assigned internal VPN IP (e.g., 10.66.x.x/32)
□ VPN server endpoint IP and port
□ Private key and server public key
```

### 1.4 Special Requirements

```
□ Devices that need VPN bypass (gaming consoles, work devices)
□ Services that need port forwarding
□ Bandwidth requirements
□ IPv6 requirements (recommend: disable)
```

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

| Template | Location |
|----------|----------|
| Network interfaces | `openwrt/network/interfaces.example` |
| Firewall zones | `openwrt/firewall/zones.example` |
| DHCP config | `openwrt/dhcp/dhcp.example` |
| VPN tunnel | `openwrt/amneziawg/awg0.conf.example` |
| AdGuard Home | `adguard/AdGuardHome.yaml.example` |
| Watchdog script | `scripts/awg-watchdog.sh` |

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
```
□ AmneziaWG packages installed (kmod-amneziawg, amneziawg-tools)
□ Config file created at /etc/amneziawg/awg0.conf
□ Permissions set (chmod 600)
□ Manual tunnel test successful
□ VPN exit IP confirmed (curl https://am.i.mullvad.net/ip)
```

### 4.3 Kill Switch
```
□ VPN firewall zone created
□ LAN→VPN forwarding enabled
□ NO LAN→WAN forwarding exists
□ Kill switch tested (ip link set awg0 down → no internet)
```

### 4.4 DNS
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

## Phase 5: Validation Tests

After deployment, run these verification tests:

```bash
# VPN active
curl -s https://am.i.mullvad.net/connected
# Expected: "You are connected to Mullvad"

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

## Error Recovery

### VPN Won't Connect
1. Verify endpoint IP is routable: `ping [VPN_SERVER_IP]`
2. Check keys match provider config
3. Verify obfuscation parameters (if AmneziaWG)
4. Try different VPN server/endpoint

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

## Communication Style

When helping users:

1. **Explain the "why"** — Users should understand what each step accomplishes
2. **Verify before proceeding** — Confirm each step works before moving on
3. **Preserve connectivity** — Always ensure user can recover SSH access
4. **Backup configs** — Before major changes, save current state
5. **Test incrementally** — Don't make multiple changes at once

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

*This document is designed for AI coding agents. Give your agent access to this entire repository for optimal results.*
