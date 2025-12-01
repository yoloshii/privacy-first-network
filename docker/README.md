# Privacy Router - Docker Deployment (Option C)

## What This Is (And Isn't)

**This is a VPN gateway add-on** - a container that provides VPN tunneling, kill switch, and DNS filtering. It runs on your existing Linux server, NAS, or VM.

**This is NOT a router replacement.** Unlike Options A & B (which deploy OpenWrt as a full router OS), this container doesn't do DHCP, WiFi, or general routing. Your existing router keeps those jobs.

| Feature | Options A/B (OpenWrt) | Option C (Docker) |
|---------|----------------------|-------------------|
| AmneziaWG obfuscation | ✅ | ✅ |
| AdGuard DNS filtering | ✅ | ✅ |
| Kill switch | ✅ | ✅ |
| Watchdog recovery | ✅ | ✅ |
| Replaces your router | ✅ Yes | ❌ No |
| Runs on existing server | ❌ No | ✅ Yes |

```
How Option C fits into your network:

Modem → [Your Existing Router] → All Devices
                  ↓
         [This Docker Container]
         (on server/NAS/VM)

Devices that want VPN protection point their gateway + DNS
to the container's IP. Other devices use router normally.
```

> **Who should use this:** Users with an existing Linux server, NAS, or VM who want to add VPN protection without dedicated hardware. Comfortable with Docker and basic networking.

> **Who should use Options A/B instead:** Users who want a dedicated privacy router appliance, or don't have a server to run Docker on. See [DEPLOYMENT.md](../docs/DEPLOYMENT.md).

---

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Docker Host                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              privacy-router container                 │  │
│  │  ┌─────────────┐      ┌──────────────────────────┐   │  │
│  │  │  AdGuard    │      │      AmneziaWG           │   │  │
│  │  │  Home       │◄────►│  (VPN Client + Gateway)  │   │  │
│  │  │  :53 DNS    │      │                          │   │  │
│  │  └─────────────┘      └──────────┬───────────────┘   │  │
│  │                                  │ awg0              │  │
│  └──────────────────────────────────┼───────────────────┘  │
│                                     │                      │
│  ┌──────────────────────────────────┴───────────────────┐  │
│  │                macvlan network                       │  │
│  │              Container IP: 192.168.1.250             │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────┬───────────────────────┘
                                      │
                        ┌─────────────▼─────────────┐
                        │     LAN: 192.168.1.0/24   │
                        │   Gateway: 192.168.1.1    │
                        └───────────────────────────┘
```

## Prerequisites

- Docker Engine 24.0+ with Compose V2
- Linux host with kernel 5.6+ (for WireGuard)
- LAN interface available for macvlan (e.g., `eth0`, `enp3s0`)
- VPN subscription (Mullvad, IVPN, or AmneziaVPN)

## Quick Start

### 1. Clone and Configure

```bash
cd docker/

# Copy environment template
cp .env.example .env

# Copy VPN config template
cp config/awg0.conf.example config/awg0.conf
```

### 2. Edit `.env`

```bash
# Required - Get from your VPN provider
VPN_IP=10.68.xxx.xxx/32              # Your assigned VPN IP
VPN_ENDPOINT_IP=xxx.xxx.xxx.xxx      # VPN server IP
VPN_ENDPOINT_PORT=51820              # Usually 51820

# Network - Adjust for your LAN
LAN_INTERFACE=eth0                   # Your Docker host's LAN interface
LAN_SUBNET=192.168.1.0/24
LAN_GATEWAY=192.168.1.1
CONTAINER_LAN_IP=192.168.1.250       # IP for container on your LAN
```

### 3. Edit `config/awg0.conf`

Fill in your VPN credentials from your provider:

```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY_HERE

# AmneziaWG obfuscation parameters
# These add CLIENT-SIDE obfuscation - servers don't need AmneziaWG support.
# The defaults below work with ANY standard WireGuard server (Mullvad, IVPN, etc.)
# Source: wgtunnel compatibility mode (https://github.com/zaneschepke/wgtunnel)
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
PublicKey = SERVER_PUBLIC_KEY_HERE
Endpoint = ${VPN_ENDPOINT_IP}:${VPN_ENDPOINT_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### 4. Deploy

```bash
docker compose up -d
```

### 5. Verify

```bash
# Quick check
docker exec privacy-router /opt/scripts/quick-test.sh

# Full validation (includes kill switch test)
docker exec privacy-router /opt/scripts/test-suite.sh
```

## Configure LAN Clients

Point your devices to use the container as gateway and DNS:

| Setting | Value |
|---------|-------|
| Gateway | 192.168.1.250 (CONTAINER_LAN_IP) |
| DNS | 192.168.1.250 |

Or configure your router's DHCP to distribute these settings automatically.

## AdGuard Home Setup

Access the web UI at: `http://192.168.1.250:3000`

1. Complete initial setup wizard
2. Set upstream DNS (recommended: DoH)
3. Enable blocklists
4. Configure client settings

Alternatively, copy the example config:
```bash
cp config/AdGuardHome.yaml.example config/AdGuardHome.yaml
```

## Management

```bash
# View logs
docker compose logs -f

# View VPN status
docker exec privacy-router amneziawg show awg0

# Check exit IP
docker exec privacy-router curl -s https://ipinfo.io/ip

# Restart container
docker compose restart

# Stop
docker compose down

# Update
docker compose pull && docker compose up -d
```

## Testing

### Quick Test (~10 seconds)
```bash
docker exec privacy-router /opt/scripts/quick-test.sh
```

Validates:
- VPN interface UP
- Handshake active
- Tunnel connectivity
- Exit IP
- Kill switch rules

### Full Test Suite (~60 seconds)
```bash
docker exec privacy-router /opt/scripts/test-suite.sh
```

**10 comprehensive tests including:**
- VPN interface exists and UP
- Handshake active
- Tunnel connectivity (ping)
- Exit IP retrieved
- Exit IP differs from LAN IP
- **Kill switch verification** (temporarily drops VPN to test)
- DNS resolution
- Ad blocking (doubleclick.net)
- No IPv6 leaks
- iptables rules present

## Kill Switch

The kill switch is **always active** and cannot be disabled. It ensures:

- **Default DROP** policy on all chains
- **Only allows:**
  - Loopback traffic
  - LAN subnet traffic
  - UDP to VPN endpoint (encrypted tunnel only)
  - Traffic through `awg0` interface

If the VPN disconnects, ALL internet traffic is blocked until reconnection.

## Troubleshooting

### Container won't start
```bash
# Check logs
docker compose logs privacy-router

# Verify TUN device
ls -la /dev/net/tun

# Check config file
docker exec privacy-router cat /etc/amneziawg/awg0.conf
```

### No handshake
```bash
# Check endpoint reachability (before VPN)
ping -c 3 YOUR_VPN_ENDPOINT_IP

# Check config
docker exec privacy-router amneziawg show awg0
```

### macvlan not working
```bash
# Verify interface name matches
ip link show

# Check for IP conflicts
ping 192.168.1.250

# Docker macvlan limitation: Host cannot reach container
# Access container from another LAN device or use bridge network
```

### DNS not working
```bash
# Test from container
docker exec privacy-router nslookup google.com

# Check AdGuard is running
docker compose logs adguard
```

### Watchdog keeps restarting tunnel
```bash
# View watchdog logs
docker exec privacy-router tail -f /var/log/awg-watchdog.log

# Increase fail threshold if network is flaky
# Edit .env: WATCHDOG_FAIL_THRESHOLD=5
```

## Obfuscation Profiles (AmneziaWG 1.5)

Choose your obfuscation level in `.env`:

```bash
AWG_PROFILE=quic  # Enable QUIC protocol mimic
```

| Profile | DPI Resistance | Use Case |
|---------|----------------|----------|
| `basic` | Medium | Home ISP, light censorship (default) |
| `quic` | High | Moderate DPI, traffic appears as HTTP/3 |
| `dns` | Medium | Environments where DNS traffic is allowed |
| `sip` | Medium | Environments where VoIP traffic is common |
| `stealth` | Maximum | Heavy censorship, aggressive DPI |

**All profiles work with standard WireGuard servers** (Mullvad, IVPN, Proton, etc.). The obfuscation is client-side only.

**Switching profiles:**
```bash
# Edit .env
AWG_PROFILE=quic

# Restart container
docker compose restart
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VPN_IP` | *required* | VPN internal IP (e.g., 10.68.x.x/32) |
| `VPN_ENDPOINT_IP` | *required* | VPN server IP address |
| `VPN_ENDPOINT_PORT` | 51820 | VPN server port |
| `LAN_INTERFACE` | eth0 | Host's LAN interface |
| `LAN_SUBNET` | 192.168.1.0/24 | Local network CIDR |
| `LAN_GATEWAY` | 192.168.1.1 | LAN router IP |
| `CONTAINER_LAN_IP` | 192.168.1.250 | Container's LAN IP |
| `AWG_PROFILE` | basic | Obfuscation profile (basic/quic/dns/sip/stealth) |
| `WATCHDOG_ENABLED` | true | Enable auto-recovery |
| `WATCHDOG_INTERVAL` | 30 | Seconds between checks |
| `WATCHDOG_FAIL_THRESHOLD` | 3 | Failures before restart |
| `PROBE_TARGETS` | 1.1.1.1 8.8.8.8 9.9.9.9 | IPs to ping for health |
| `EXPECTED_EXIT_IP` | *optional* | Expected exit IP (strict mode) |

## Files

```
docker/
├── Dockerfile              # AmneziaWG client image
├── docker-compose.yml      # Service definitions
├── .env.example            # Environment template
├── config/
│   ├── awg0.conf.example   # VPN config template
│   ├── postup.sh           # Kill switch rules
│   ├── predown.sh          # Cleanup on stop
│   └── AdGuardHome.yaml.example  # DNS config template
└── scripts/
    ├── entrypoint.sh       # Container startup
    ├── healthcheck.sh      # Docker health check
    ├── watchdog.sh         # Auto-recovery daemon
    ├── test-suite.sh       # Full validation (10 tests)
    └── quick-test.sh       # Fast daily check
```

## Security Notes

1. **Kill switch is mandatory** - Cannot be disabled
2. **IPv6 is fully blocked** - Prevents leaks
3. **DNS queries go through VPN** - No DNS leaks
4. **Config files contain secrets** - Keep `awg0.conf` private
5. **Container needs elevated privileges** - NET_ADMIN, SYS_MODULE required

## License

MIT License - See repository root.
