# How It Works - Technical Deep Dive

This document explains the technical implementation details for network engineers and curious users.

## Table of Contents

1. [Network Layer Model](#network-layer-model)
2. [Routing Architecture](#routing-architecture)
3. [Kill Switch Implementation](#kill-switch-implementation)
4. [VPN Tunnel Mechanics](#vpn-tunnel-mechanics)
5. [DNS Resolution Chain](#dns-resolution-chain)
6. [Watchdog Recovery System](#watchdog-recovery-system)
7. [AmneziaWG Obfuscation](#amneziawg-obfuscation)

---

## Network Layer Model

Understanding how traffic flows through the OSI layers:

```
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 7 (Application)                                           │
│ HTTP request: GET /r/privacy HTTP/1.1                          │
│ Host: reddit.com                                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 4 (Transport)                                             │
│ TCP segment                                                     │
│ src_port: 54321, dst_port: 443 (HTTPS)                         │
│ Flags: SYN (new connection)                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 3 (Network) - INNER PACKET                                │
│ IP header                                                       │
│ src: 10.x.x.x (VPN internal IP)                                │
│ dst: 151.101.1.140 (reddit.com)                                │
│ protocol: TCP                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
            VPN ENCAPSULATION │ (WireGuard encrypts everything above)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 4 (Transport) - OUTER                                     │
│ UDP segment                                                     │
│ src_port: 51820, dst_port: 51820                               │
│ payload: [encrypted inner packet + WG headers]                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 3 (Network) - OUTER PACKET                                │
│ IP header                                                       │
│ src: <your_wan_ip>                                             │
│ dst: <vpn_server_ip>                                           │
│ protocol: UDP                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 2 (Data Link)                                             │
│ Ethernet frame                                                  │
│ src_mac: <router_mac>                                          │
│ dst_mac: <gateway_mac>                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    Physical transmission
```

**Key insight:** Your ISP only sees the outer packet - encrypted UDP to some IP address. The inner packet (your actual destination) is completely hidden.

---

## Routing Architecture

### Routing Table Structure

```bash
# Normal operation (VPN up)
default dev awg0 scope link                    # All traffic via VPN
<vpn_endpoint> via <wan_gateway> dev eth0     # VPN server reachable via WAN

# VPN down (kill switch active)
<vpn_endpoint> via <wan_gateway> dev eth0     # Endpoint route remains
# NO default route = all internet traffic dropped
```

### Route Decision Process

```
Packet arrives from LAN device
         │
         ▼
┌─────────────────────────┐
│ Destination IP check    │
│ Is it local network?    │
└─────────────────────────┘
         │
    ┌────┴────┐
    │         │
   YES        NO
    │         │
    ▼         ▼
┌────────┐  ┌─────────────────────┐
│ Local  │  │ Route table lookup  │
│ bridge │  │ Match: default dev  │
│ forward│  │ awg0                │
└────────┘  └─────────────────────┘
                    │
                    ▼
           ┌───────────────┐
           │ Firewall      │
           │ zone check    │
           │ lan→vpn: OK   │
           └───────────────┘
                    │
                    ▼
           ┌───────────────┐
           │ NAT (MASQ)    │
           │ src→VPN_IP    │
           └───────────────┘
                    │
                    ▼
           ┌───────────────┐
           │ awg0 encrypt  │
           │ + encapsulate │
           └───────────────┘
                    │
                    ▼
           ┌───────────────┐
           │ Route lookup  │
           │ endpoint via  │
           │ wan gateway   │
           └───────────────┘
                    │
                    ▼
               To Internet
```

### Critical: Endpoint Route

The VPN endpoint must be reachable via the WAN gateway, not the VPN tunnel itself (would create a loop):

```
WRONG:
  default via awg0
  (vpn_endpoint routed via awg0 = infinite loop, tunnel never connects)

CORRECT:
  default via awg0
  vpn_endpoint via wan_gateway dev eth0  ← This route MUST exist
```

---

## Kill Switch Implementation

### Firewall Zone Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     NFTABLES FIREWALL                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │    LAN ZONE     │    │    VPN ZONE     │                    │
│  │  ┌───────────┐  │    │  ┌───────────┐  │                    │
│  │  │ br-lan    │  │    │  │ awg0      │  │                    │
│  │  └───────────┘  │    │  └───────────┘  │                    │
│  │                 │    │                 │                    │
│  │ input: ACCEPT   │    │ input: REJECT   │                    │
│  │ output: ACCEPT  │    │ output: ACCEPT  │                    │
│  │ forward: ACCEPT │    │ forward: REJECT │                    │
│  └────────┬────────┘    └────────▲────────┘                    │
│           │                      │                              │
│           │  ┌────────────────┐  │                              │
│           └──│ FORWARDING     │──┘                              │
│              │ lan → vpn: ✓   │                                 │
│              │ lan → wan: ✗   │  ← KILL SWITCH                  │
│              └────────────────┘                                 │
│                                                                 │
│  ┌─────────────────┐                                           │
│  │    WAN ZONE     │                                           │
│  │  ┌───────────┐  │                                           │
│  │  │ eth0      │  │                                           │
│  │  └───────────┘  │                                           │
│  │                 │                                           │
│  │ input: REJECT   │  (only VPN endpoint UDP allowed out)      │
│  │ output: ACCEPT  │                                           │
│  │ forward: REJECT │                                           │
│  └─────────────────┘                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why Traffic Cannot Leak

**Scenario: VPN tunnel goes down**

```
1. awg0 interface state → DOWN
2. Kernel removes routes associated with awg0
3. Routing table now has NO default route
4. LAN device sends packet to internet
5. Kernel: "No route to host" → packet dropped

Even if attacker adds route:
6. ip route add default via <wan_gateway>
7. Packet goes to routing → matches default
8. Firewall check: lan → wan forwarding?
9. Firewall: "No rule for lan→wan" → REJECT
10. Packet dropped by firewall

Double protection: routing + firewall
```

### LAN Management During Kill Switch

```
Device (192.168.1.100) → OpenWrt (192.168.1.1)
                              │
                              ▼
                    ┌─────────────────┐
                    │ Destination:    │
                    │ 192.168.1.1     │
                    │ (local address) │
                    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ INPUT chain     │
                    │ from lan zone   │
                    │ → ACCEPT        │
                    └─────────────────┘
                              │
                              ▼
                    SSH/HTTP works ✓

Note: Traffic TO the router (input) is separate from
      traffic THROUGH the router (forward).
      Kill switch only affects forwarding.
```

---

## VPN Tunnel Mechanics

### WireGuard Cryptography

```
┌─────────────────────────────────────────────────────────────────┐
│                    WIREGUARD HANDSHAKE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CLIENT                              SERVER                     │
│    │                                    │                       │
│    │  1. Initiation                     │                       │
│    │  ─────────────────────────────────►│                       │
│    │  [client_ephemeral_pub,            │                       │
│    │   encrypted(client_static_pub,     │                       │
│    │              timestamp)]           │                       │
│    │                                    │                       │
│    │  2. Response                       │                       │
│    │  ◄─────────────────────────────────│                       │
│    │  [server_ephemeral_pub,            │                       │
│    │   encrypted(empty)]                │                       │
│    │                                    │                       │
│    │  3. Data (both directions)         │                       │
│    │  ◄────────────────────────────────►│                       │
│    │  [counter, encrypted(payload)]     │                       │
│    │                                    │                       │
│  Crypto: ChaCha20-Poly1305, Curve25519, BLAKE2s                │
│  Key rotation: Every 2 minutes or 2^64 messages                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Tunnel Interface Creation (Manual)

```bash
# 1. Create WireGuard interface
ip link add dev awg0 type amneziawg

# 2. Apply configuration (keys, endpoint, allowed IPs)
amneziawg setconf awg0 /etc/amneziawg/awg0.conf

# 3. Assign internal VPN IP
ip address add 10.x.x.x/32 dev awg0

# 4. Bring interface up
ip link set up dev awg0

# 5. Add routes
ip route add <vpn_endpoint> via <wan_gateway>  # Endpoint via WAN
ip route add default dev awg0                   # Everything else via VPN
```

### Configuration File Structure

```ini
[Interface]
PrivateKey = <base64_private_key>
# AmneziaWG obfuscation parameters
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
PublicKey = <server_public_key>
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = <server_ip>:51820
PersistentKeepalive = 25
```

---

## DNS Resolution Chain

### Query Flow

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. DEVICE DNS QUERY                                              │
│    Browser: "resolve reddit.com"                                 │
│    System resolver: send to 192.168.1.5 (AdGuard - from DHCP)   │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ 2. ADGUARD HOME PROCESSING                                       │
│    ┌────────────────────────────────────────────────────────┐   │
│    │ Check blocklists:                                       │   │
│    │ - reddit.com in blocklist? NO                          │   │
│    │ - Need upstream resolution                              │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌────────────────────────────────────────────────────────┐   │
│    │ If BLOCKED (e.g., doubleclick.net):                    │   │
│    │ - Return 0.0.0.0 immediately                           │   │
│    │ - No upstream query (saves bandwidth)                  │   │
│    └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ 3. DNS-OVER-HTTPS UPSTREAM                                       │
│    AdGuard → HTTPS POST to https://adblock.dns.mullvad.net/dns-query│
│    ┌────────────────────────────────────────────────────────┐   │
│    │ TLS connection established                              │   │
│    │ DNS query sent as HTTP/2 payload                       │   │
│    │ ISP sees: "HTTPS to Mullvad IP" (cannot see query)    │   │
│    └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ 4. VPN PROVIDER DNS (Mullvad)                                    │
│    - Receives encrypted DNS query                                │
│    - Performs resolution (no logging policy)                     │
│    - Additional blocklists applied (if using adblock DNS)       │
│    - Returns: reddit.com → 151.101.1.140                        │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ 5. RESPONSE CHAIN                                                │
│    Mullvad DNS → AdGuard → Cache → Device                       │
│    Total time: ~50-200ms (cached: <5ms)                         │
└──────────────────────────────────────────────────────────────────┘
```

### DHCP DNS Push

```bash
# OpenWrt DHCP option 6 pushes DNS server to clients
# /etc/config/dhcp
config dhcp 'lan'
    option dhcpv4 'server'
    list dhcp_option '6,192.168.1.5'  # AdGuard Home IP

# Clients receive:
# DNS Server: 192.168.1.5 (not router, not ISP)
```

### DNS Leak Prevention

```
┌─────────────────────────────────────────────────────────────────┐
│ POTENTIAL LEAK VECTORS                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 1. System resolver bypass → BLOCKED                             │
│    App sends DNS directly to 8.8.8.8                           │
│    Route: 8.8.8.8 → default → awg0 → VPN → exit                │
│    ISP sees: encrypted traffic to VPN (not DNS to Google)      │
│                                                                 │
│ 2. Router DNS leak → PREVENTED                                  │
│    OpenWrt's own DNS set to Mullvad (100.64.0.4)               │
│    All router-originated queries go through VPN                 │
│                                                                 │
│ 3. IPv6 DNS → DISABLED                                          │
│    IPv6 completely disabled (sysctl + UCI)                     │
│    No IPv6 DNS queries possible                                 │
│                                                                 │
│ 4. DoH to VPN DNS → ENCRYPTED                                   │
│    AdGuard uses HTTPS to Mullvad DNS                           │
│    Even inside VPN tunnel, DNS is encrypted                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Watchdog Recovery System

### State Machine

```
┌─────────────────────────────────────────────────────────────────┐
│                   WATCHDOG STATE MACHINE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ┌──────────────┐                                            │
│    │   HEALTHY    │◄────────────────────────────────┐          │
│    │ fail_count=0 │                                  │          │
│    └──────┬───────┘                                  │          │
│           │                                          │          │
│           │ ping fails                               │          │
│           ▼                                          │          │
│    ┌──────────────┐                                  │          │
│    │  DEGRADED    │                                  │          │
│    │ fail_count=1 │                                  │          │
│    └──────┬───────┘                                  │          │
│           │                                          │          │
│           │ ping fails                   ping succeeds          │
│           ▼                                          │          │
│    ┌──────────────┐                                  │          │
│    │  DEGRADED    │──────────────────────────────────┘          │
│    │ fail_count=2 │                                             │
│    └──────┬───────┘                                             │
│           │                                                     │
│           │ ping fails                                          │
│           ▼                                                     │
│    ┌──────────────┐      restart_tunnel()      ┌────────────┐  │
│    │   FAILED     │ ──────────────────────────►│ RECOVERING │  │
│    │ fail_count=3 │                            │            │  │
│    └──────────────┘                            └──────┬─────┘  │
│                                                       │         │
│                                                       │ wait 5s │
│                                                       ▼         │
│                                                ┌──────────────┐ │
│                                                │   HEALTHY    │ │
│                                                │ fail_count=0 │ │
│                                                └──────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Recovery Procedure

```bash
restart_tunnel() {
    # 1. TEARDOWN - Remove existing interface
    ip link del dev awg0 2>/dev/null
    sleep 1  # Allow kernel cleanup

    # 2. RECREATE - Fresh interface
    ip link add dev awg0 type amneziawg

    # 3. CONFIGURE - Apply WireGuard config
    amneziawg setconf awg0 /etc/amneziawg/awg0.conf

    # 4. ADDRESS - Assign VPN internal IP
    ip address add $VPN_IP/32 dev awg0

    # 5. ACTIVATE - Bring interface up
    ip link set up dev awg0

    # 6. ROUTING (CRITICAL ORDER)
    #    Endpoint route MUST come before default route
    ip route add $ENDPOINT_IP via $WAN_GATEWAY 2>/dev/null

    # 7. DEFAULT ROUTE - All traffic via VPN
    ip route del default 2>/dev/null
    ip route add default dev awg0
}
```

### Why Route Order Matters

```
WRONG ORDER:
1. ip route add default dev awg0
2. ip route add $ENDPOINT via $GATEWAY

Problem:
- Step 1: All traffic goes to awg0 (including VPN endpoint)
- VPN handshake packets go to awg0... which needs VPN to work
- Infinite loop, tunnel never establishes

CORRECT ORDER:
1. ip route add $ENDPOINT via $GATEWAY
2. ip route add default dev awg0

Correct flow:
- Step 1: VPN endpoint reachable via WAN (not via VPN)
- Step 2: Everything else goes via VPN
- VPN handshake works because endpoint route exists
```

---

## AmneziaWG Obfuscation

### Standard WireGuard Fingerprint

```
┌─────────────────────────────────────────────────────────────────┐
│ STANDARD WIREGUARD PACKET                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Byte 0:  Message Type (1-4)     ← Identifiable!               │
│  Bytes 1-3: Reserved (zeros)     ← Identifiable!               │
│  Bytes 4+: Type-specific data                                   │
│                                                                 │
│  Handshake Initiation (type 1):                                │
│  [01 00 00 00] [sender] [ephemeral] [static] [timestamp] [mac] │
│       ↑                                                         │
│       └── DPI: "This is WireGuard!"                            │
│                                                                 │
│  Packet sizes also predictable:                                │
│  - Initiation: 148 bytes                                       │
│  - Response: 92 bytes                                          │
│  - Data: variable but patterns visible                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### AmneziaWG Obfuscation

```
┌─────────────────────────────────────────────────────────────────┐
│ AMNEZIAWG PACKET WITH Jc=4, Jmin=40, Jmax=70                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [random junk: 40-70 bytes] [modified header] [payload]        │
│        ↑                          ↑                             │
│        │                          └── Header values shifted    │
│        └── Random padding (Jc packets of Jmin-Jmax bytes)      │
│                                                                 │
│  Parameters:                                                    │
│  - Jc: Number of junk packets to prepend (init handshake)      │
│  - Jmin: Minimum junk packet size                              │
│  - Jmax: Maximum junk packet size                              │
│  - S1, S2: Init packet magic header manipulation               │
│  - H1-H4: Header field obfuscation values                      │
│                                                                 │
│  Result:                                                        │
│  - No fixed header pattern                                      │
│  - Variable packet sizes                                        │
│  - Looks like random UDP traffic                               │
│  - DPI cannot distinguish from noise                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Values

```ini
# Conservative (light obfuscation, lower overhead)
Jc = 3
Jmin = 20
Jmax = 50

# Aggressive (heavy obfuscation, more overhead)
Jc = 8
Jmin = 50
Jmax = 1000

# Balanced (recommended)
Jc = 4
Jmin = 40
Jmax = 70

# Note: Both client and server MUST use identical values
# Different values = handshake failure
```

---

## Performance Considerations

### Latency Impact

```
Without VPN:
Device → ISP → Destination
~20ms local, ~100ms international

With VPN:
Device → ISP → VPN Server → Destination
+20-50ms overhead (encryption + extra hop)

With VPN + DoH:
Additional ~10-20ms for DNS (cached queries: <5ms)

Total typical overhead: 30-70ms
```

### Throughput

```
WireGuard performance (rough estimates):
- Raspberry Pi 4: 300-400 Mbps
- x86 mini PC: 800-1000 Mbps
- Modern server: Line rate

AmneziaWG overhead:
- ~5-10% additional CPU for obfuscation
- Minimal bandwidth overhead from junk packets
```

### Optimization Tips

```
1. Use kernel-mode WireGuard (not userspace)
2. Enable hardware crypto acceleration if available
3. Reduce Jc value if obfuscation not critical
4. Use geographically close VPN server
5. Enable DNS caching (AdGuard does this automatically)
```
