# Privacy Router Architecture

A privacy-focused home router stack that routes all traffic through an obfuscated VPN tunnel with automatic failover, DNS-level ad blocking, and a hardware kill switch.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PRIVACY ROUTER STACK                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Internet                                                                   │
│       │                                                                      │
│       ▼                                                                      │
│   ┌───────────┐                                                              │
│   │  Modem/   │  Your ISP connection                                         │
│   │  ONT      │  (receives public IP)                                        │
│   └─────┬─────┘                                                              │
│         │                                                                    │
│         ▼                                                                    │
│   ┌─────────────────────────────────────────────────────┐                   │
│   │              OPENWRT ROUTER                         │                   │
│   │  ┌─────────────────────────────────────────────┐   │                   │
│   │  │  WAN Interface                              │   │                   │
│   │  │  - DHCP from modem                          │   │                   │
│   │  │  - Endpoint route to VPN server             │   │                   │
│   │  └─────────────────────────────────────────────┘   │                   │
│   │                      │                              │                   │
│   │                      ▼                              │                   │
│   │  ┌─────────────────────────────────────────────┐   │                   │
│   │  │  AMNEZIAWG TUNNEL (awg0)                    │   │                   │
│   │  │  - Obfuscated WireGuard (DPI-resistant)     │   │                   │
│   │  │  - Default route for all traffic            │   │                   │
│   │  │  - Kill switch (no bypass possible)         │   │                   │
│   │  └─────────────────────────────────────────────┘   │                   │
│   │                      │                              │                   │
│   │                      ▼                              │                   │
│   │  ┌─────────────────────────────────────────────┐   │                   │
│   │  │  LAN Interface (br-lan)                     │   │                   │
│   │  │  - Gateway for all LAN devices              │   │                   │
│   │  │  - DHCP server (assigns IPs + DNS)          │   │                   │
│   │  │  - Forwards to VPN zone ONLY                │   │                   │
│   │  └─────────────────────────────────────────────┘   │                   │
│   └─────────────────────────────────────────────────────┘                   │
│         │                                    │                               │
│         │ DNS queries                        │ All other traffic             │
│         ▼                                    │                               │
│   ┌─────────────┐                           │                               │
│   │  ADGUARD    │                           │                               │
│   │   HOME      │                           │                               │
│   │  - Blocks   │                           │                               │
│   │    ads/     │                           │                               │
│   │    trackers │                           │                               │
│   │  - DoH to   │                           │                               │
│   │    VPN DNS  │                           │                               │
│   └─────────────┘                           │                               │
│         │                                    │                               │
│         └────────────────┬───────────────────┘                               │
│                          │                                                   │
│                          ▼                                                   │
│   ┌─────────────────────────────────────────────────────┐                   │
│   │              WIRELESS ACCESS POINT                  │                   │
│   │  (Existing router in AP/Bridge mode)                │                   │
│   │  - WiFi only, no routing                            │                   │
│   │  - Passes all traffic to OpenWrt                    │                   │
│   └─────────────────────────────────────────────────────┘                   │
│                          │                                                   │
│                          ▼                                                   │
│   ┌─────────────────────────────────────────────────────┐                   │
│   │                 YOUR DEVICES                         │                   │
│   │  Phones, laptops, smart TVs, IoT devices            │                   │
│   │  - All traffic tunneled through VPN                 │                   │
│   │  - All DNS filtered through AdGuard                 │                   │
│   │  - Protected by kill switch                         │                   │
│   └─────────────────────────────────────────────────────┘                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. OpenWrt Router

The core routing platform running on dedicated hardware (Raspberry Pi, x86 mini PC), virtual machine, or container.

**Responsibilities:**
- WAN connection management (DHCP from ISP modem)
- VPN tunnel establishment and maintenance
- Kill switch enforcement via firewall zones
- DHCP server for LAN devices
- Traffic routing (LAN → VPN only)

**Key Features:**
- Stateless firewall with zone-based policies
- No LAN→WAN forwarding (traffic cannot bypass VPN)
- Automatic tunnel recovery via watchdog script
- Boot persistence for unattended operation

### 2. AmneziaWG VPN Tunnel

An obfuscated fork of WireGuard that resists Deep Packet Inspection (DPI).

**Why AmneziaWG over standard WireGuard:**
- Standard WireGuard has identifiable packet patterns
- DPI systems can detect and block WireGuard traffic
- AmneziaWG adds junk packets (Jc/Jmin/Jmax parameters) to disguise traffic
- Appears as random UDP noise to network observers

**Configuration:**
- Connects to privacy-focused VPN provider (Mullvad, IVPN, etc.)
- Uses provider's ad-blocking DNS servers
- Receives internal VPN IP for tunnel communication

### 3. AdGuard Home DNS Server

A network-wide ad/tracker blocker operating at DNS level.

**Responsibilities:**
- Resolves DNS queries for all LAN devices
- Blocks ads, trackers, malware domains
- Upstream queries via DNS-over-HTTPS (DoH) to VPN provider
- Provides encrypted DNS to prevent ISP snooping

**Benefits:**
- Blocks ads in apps that don't support browser extensions
- Reduces bandwidth (blocked requests never load)
- Single point of control for all devices
- No client-side software required

### 4. Kill Switch

A firewall architecture that prevents any traffic from bypassing the VPN.

**Implementation:**
```
Firewall Zones:
├── LAN Zone
│   ├── input: ACCEPT (management access)
│   ├── output: ACCEPT
│   └── forward: ACCEPT (within zone)
│
├── VPN Zone (awg0)
│   ├── input: REJECT
│   ├── output: ACCEPT
│   ├── forward: REJECT
│   └── masquerade: enabled
│
└── WAN Zone
    ├── input: REJECT
    ├── output: ACCEPT (for VPN endpoint only)
    └── forward: REJECT

Forwarding Rules:
├── LAN → VPN: ALLOWED ✓
├── LAN → WAN: BLOCKED ✗ (kill switch)
└── VPN → WAN: BLOCKED ✗
```

**Behavior:**
- VPN up: All traffic flows through tunnel
- VPN down: All internet traffic blocked, LAN still accessible
- No manual intervention required - automatic protection

### 5. Watchdog Service

A background script that monitors tunnel health and performs recovery.

**Features:**
- Checks connectivity every 30 seconds
- Restarts tunnel after 3 consecutive failures
- Adds correct routes after tunnel restart
- Logs all events for troubleshooting

## Security Model

### Threat Protection

| Threat | Protection |
|--------|------------|
| ISP surveillance | All traffic encrypted through VPN tunnel |
| DNS leaks | AdGuard uses DoH to VPN provider's DNS |
| VPN failure leaks | Kill switch blocks all non-VPN traffic |
| IP address exposure | VPN provider's exit IP shown to websites |
| DPI/VPN blocking | AmneziaWG obfuscation disguises traffic |
| Ad/tracker networks | DNS-level blocking via AdGuard |
| IPv6 leaks | IPv6 disabled at all levels |

### What This Does NOT Protect Against

- Malware on your devices (use endpoint security)
- WebRTC leaks (disable in browser settings)
- Browser fingerprinting (use privacy browsers)
- Logging by websites you authenticate to
- Physical access to your network
- Compromised VPN provider

## Network Flow

### Outbound Request (e.g., loading reddit.com)

```
1. DEVICE → DNS QUERY
   Your phone asks: "What IP is reddit.com?"

2. DNS RESOLUTION (AdGuard)
   AdGuard checks blocklist → reddit.com NOT blocked
   AdGuard queries upstream via DoH → gets 151.101.1.140
   Returns answer to device

3. DEVICE → TCP CONNECTION
   Phone sends packet: src=192.168.1.x, dst=151.101.1.140

4. OPENWRT ROUTING
   Packet arrives on LAN interface
   Routing table: default via awg0
   Forward to VPN zone ✓

5. VPN ENCAPSULATION
   Original packet encrypted
   Wrapped in new packet: src=router_wan_ip, dst=vpn_server_ip
   AmneziaWG adds obfuscation

6. WAN TRANSMISSION
   Encrypted packet sent to VPN server via ISP
   ISP sees: "encrypted UDP to some IP"

7. VPN SERVER EXIT
   VPN server decrypts
   Forwards to reddit.com
   Reddit sees: VPN exit IP (not your real IP)

8. RETURN PATH
   Reddit → VPN server → encrypted → OpenWrt → decrypt → device
```

### Kill Switch Activation

```
1. VPN TUNNEL FAILS
   awg0 interface goes down
   No default route exists

2. DEVICE TRIES TO CONNECT
   Phone sends packet to internet
   No route to destination (default route gone)
   Packet dropped by kernel

3. EVEN IF ROUTE EXISTED
   Firewall has no LAN→WAN forwarding rule
   Packet would be rejected by nftables

4. MANAGEMENT STILL WORKS
   LAN→LAN traffic stays in LAN zone
   SSH, web UI, AdGuard all accessible

5. WATCHDOG DETECTS FAILURE
   After 3 failed pings (90 seconds)
   Tunnel restarted automatically
   Internet restored
```

## Deployment Options

### Option A: Dedicated Hardware (Recommended)

```
Internet → Modem → [Raspberry Pi / Mini PC] → WiFi AP → Devices
                   └── OpenWrt + AdGuard
```

**Pros:** Simple, low power, reliable, full control
**Cons:** Requires hardware purchase

### Option B: Virtual Machine (Homelab/Enterprise)

```
Internet → Modem → [Hypervisor Host] → WiFi AP → Devices
                   ├── OpenWrt VM
                   └── AdGuard VM/Container
```

**Pros:** Leverage existing hardware, easy snapshots/backups, flexible resources
**Cons:** More complex networking (requires bridged NICs), hypervisor dependency

### Option C: Docker (Testing/Simple Setups)

```
Internet → Modem → [Linux Host with Docker] → WiFi AP → Devices
                   ├── WireGuard container
                   └── AdGuard container
```

**Pros:** Easy deployment, portable, quick testing
**Cons:** Less control, container networking complexity, requires host network mode

## Requirements

### Hardware
- Device with 2 network interfaces (WAN + LAN)
- Minimum 512MB RAM, 1 CPU core
- Ethernet for WAN connection
- Storage for logs and configs

### Software
- OpenWrt 23.05+ (or compatible Linux)
- AmneziaWG kernel module and tools
- AdGuard Home (or Pi-hole alternative)

### Network
- Existing WiFi router (to use as AP)
- VPN provider account with WireGuard support
- Static LAN IP scheme

## Next Steps

1. **[HOW-IT-WORKS.md](HOW-IT-WORKS.md)** - Deep technical explanation
2. **[DEPLOYMENT.md](DEPLOYMENT.md)** - Step-by-step installation
3. **[CONFIGURATION.md](CONFIGURATION.md)** - Config file reference
4. **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and fixes
