# Privacy Router Stack

**Network-wide VPN protection with automatic failsafe** — Route all your devices through an encrypted tunnel without installing apps on each one.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Why Network-Level VPN?

### The Problem with Per-Device VPN Apps

When you install a VPN app like Mullvad, NordVPN, or ProtonVPN on your phone or laptop, you're only protecting **that single device**. This leaves gaps:

| Device | VPN App Support | Risk |
|--------|-----------------|------|
| Smart TV | ❌ None | ISP sees all streaming |
| Gaming Console | ❌ None | IP exposed to game servers |
| IoT Devices | ❌ None | Smart home traffic visible |
| Guest Devices | ❌ Can't control | No protection |
| Work Laptop | ⚠️ May conflict | Corporate policy blocks VPN |
| Kids' Devices | ⚠️ Can be disabled | Protection bypassed |

**VPN apps also:**
- Drain battery on mobile devices
- Can be forgotten or disabled
- Require updates on every device
- May leak traffic during app crashes
- Don't protect devices that can't run apps

### The Network-Level Solution

This privacy router sits between your modem and your existing router. **Every device** on your network automatically routes through the VPN — no apps, no configuration, no exceptions.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        YOUR HOME NETWORK                            │
│                                                                     │
│   ┌──────────┐    ┌─────────────────┐    ┌──────────────────────┐  │
│   │  MODEM   │───▶│ PRIVACY ROUTER  │───▶│  YOUR EXISTING ROUTER│  │
│   │  (ISP)   │    │  (This Stack)   │    │  (WiFi/Switch)       │  │
│   └──────────┘    └─────────────────┘    └──────────────────────┘  │
│                           │                        │               │
│                     ┌─────┴─────┐           ┌──────┴──────┐        │
│                     │ ENCRYPTED │           │ ALL DEVICES │        │
│                     │  TUNNEL   │           │  PROTECTED  │        │
│                     └───────────┘           └─────────────┘        │
└─────────────────────────────────────────────────────────────────────┘
```

**Every device is protected:** Phones, tablets, laptops, smart TVs, gaming consoles, IoT devices, guests — everything.

---

## Why Not Just Use Mullvad QUIC or WireGuard Apps?

Great question. Mullvad's QUIC tunnels and WireGuard apps are excellent for individual device protection. Here's when each approach makes sense:

### VPN Apps Are Better When:
- You only need to protect 1-2 devices
- You travel frequently and use different networks
- You want per-app split tunneling
- You're on a network you don't control

### Network-Level VPN Is Better When:
- You have many devices (especially ones that can't run VPN apps)
- You want "set and forget" protection for your entire household
- You need to protect smart home/IoT devices
- You want a **kill switch that actually works** (more on this below)
- You're in a region with VPN blocking/deep packet inspection

### The Kill Switch Problem

Here's something most people don't realize: **VPN app kill switches often fail**.

When a VPN app crashes, loses connection, or during the moments between connection drops and reconnection, your traffic can leak to your ISP. App-based kill switches try to prevent this, but they operate at the application level — if the app itself crashes, the kill switch dies with it.

**This stack implements a hardware-level kill switch:**

```
Normal Operation:
  Device → Privacy Router → VPN Tunnel → Internet ✓

VPN Down (App-based kill switch):
  Device → [App crashed] → ISP sees traffic ✗

VPN Down (This stack):
  Device → Privacy Router → [No route exists] → Traffic blocked ✓
```

The kill switch is implemented in the **firewall and routing table**, not in software. If the VPN tunnel goes down, there is literally no route for traffic to take — it's not blocked by a rule that might fail, it simply has nowhere to go.

---

## Features

### Core Protection
- **Network-wide VPN** — All devices protected automatically
- **Hardware kill switch** — No traffic leaks, ever
- **DNS leak protection** — DNS queries encrypted via DoH
- **IPv6 leak prevention** — IPv6 completely disabled
- **Ad & tracker blocking** — Network-level blocking via AdGuard Home

### Reliability
- **Automatic recovery** — Watchdog restarts tunnel on failure
- **Boot persistence** — VPN starts automatically on power-up
- **Connection monitoring** — Continuous health checks

### Advanced (For Technical Users)
- **DPI bypass** — AmneziaWG obfuscation defeats deep packet inspection
- **Flexible deployment** — Dedicated hardware, VM, or Docker
- **Full observability** — Detailed logging and diagnostics

---

## How the Kill Switch Works

The kill switch is the most important security feature. Here's exactly how it works:

### Firewall Zones

```
┌─────────────────────────────────────────────────────────┐
│                    FIREWALL ZONES                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   ┌─────┐         ┌─────┐         ┌─────┐              │
│   │ LAN │───✓────▶│ VPN │         │ WAN │              │
│   └─────┘         └─────┘         └─────┘              │
│      │                               ▲                  │
│      │                               │                  │
│      └───────────✗───────────────────┘                  │
│           (NO FORWARDING ALLOWED)                       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

Traffic from LAN can **only** go to the VPN zone. There is no forwarding rule from LAN to WAN. This isn't a "block" rule that could be bypassed — the route simply doesn't exist.

### Routing Table

```bash
# When VPN is UP:
default dev awg0           # All traffic → VPN tunnel
1.2.3.4 via 192.168.1.1    # VPN server → WAN (exception)

# When VPN is DOWN:
# No default route exists
# Traffic has nowhere to go = blocked
```

### Double Protection

Even if somehow a forwarding rule existed, the routing table provides a second layer: with no default route pointing to WAN, packets would be dropped anyway.

---

## AmneziaWG: Defeating VPN Blocking

Some ISPs and countries use **Deep Packet Inspection (DPI)** to identify and block VPN traffic. Standard WireGuard has a recognizable packet signature.

**AmneziaWG** is an obfuscated fork of WireGuard that adds:

| Parameter | Purpose |
|-----------|---------|
| Jc | Junk packet count |
| Jmin/Jmax | Junk packet size range |
| S1/S2 | Init packet magic |
| H1-H4 | Header obfuscation |

These parameters make the traffic look like random noise rather than a VPN connection. Your VPN provider supplies these values.

**When do you need this?**
- ISP throttles or blocks VPN traffic
- You're in a country with VPN restrictions
- Corporate networks block WireGuard
- Standard WireGuard connections are unreliable

If your VPN works fine with regular WireGuard, you can use standard WireGuard instead — the architecture works with both.

---

## Quick Start

### Prerequisites

- **Hardware**: Raspberry Pi 4/5, x86 mini PC, VM, or any device with 2 NICs
- **VPN Account**: Mullvad, IVPN, ProtonVPN, or any WireGuard-compatible provider
- **Network Access**: Ability to place device between modem and router

### Installation Overview

1. Install OpenWrt on your device
2. Install AmneziaWG (or WireGuard)
3. Configure network interfaces
4. Set up firewall kill switch
5. Deploy AdGuard Home for DNS
6. Install watchdog for auto-recovery
7. Cut over your network

**Detailed instructions:** [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)

### Docker Deployment

For testing or simpler setups:

```bash
cp docker/.env.example docker/.env
# Edit .env with your VPN credentials
docker-compose up -d
```

**Note:** Docker deployment requires host networking and has limitations compared to dedicated hardware. See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for details.

---

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, components, security model |
| [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | Deep technical dive into every component |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Step-by-step installation guide |
| [CONFIGURATION.md](docs/CONFIGURATION.md) | Complete configuration reference |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |

---

## Network Diagram

```
                                    INTERNET
                                        │
                            ┌───────────┴───────────┐
                            │     VPN Provider      │
                            │   (Mullvad/IVPN/etc)  │
                            └───────────┬───────────┘
                                        │
                              Encrypted WireGuard
                                     Tunnel
                                        │
┌───────────────────────────────────────┼───────────────────────────────────────┐
│ YOUR HOME                             │                                       │
│                                       │                                       │
│    ┌──────────┐              ┌────────┴────────┐              ┌──────────┐   │
│    │   ISP    │    WAN       │                 │    LAN       │  WiFi    │   │
│    │  MODEM   │─────────────▶│ PRIVACY ROUTER  │─────────────▶│  ROUTER  │   │
│    │          │  (Untrusted) │                 │  (Protected) │          │   │
│    └──────────┘              │  ┌───────────┐  │              └────┬─────┘   │
│                              │  │ AdGuard   │  │                   │         │
│                              │  │ DNS + Ads │  │                   │         │
│                              │  └───────────┘  │              ┌────┴─────┐   │
│                              │  ┌───────────┐  │              │ DEVICES  │   │
│                              │  │ Kill      │  │              │          │   │
│                              │  │ Switch    │  │              │ Phone    │   │
│                              │  └───────────┘  │              │ Laptop   │   │
│                              │  ┌───────────┐  │              │ Smart TV │   │
│                              │  │ Watchdog  │  │              │ Console  │   │
│                              │  │ Recovery  │  │              │ IoT      │   │
│                              │  └───────────┘  │              └──────────┘   │
│                              └─────────────────┘                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

Traffic Flow:
  Device → WiFi Router → Privacy Router → VPN Tunnel → VPN Server → Internet
                              │
                    DNS: AdGuard (DoH) ─────────────▶ VPN Provider DNS

Kill Switch:
  If VPN down → No route to internet → All traffic blocked (not leaked)
```

---

## Comparison: This Stack vs VPN Apps

| Feature | VPN App | This Stack |
|---------|---------|------------|
| Devices protected | 1 per install | All on network |
| Smart TV/Console | ❌ | ✓ |
| IoT devices | ❌ | ✓ |
| Battery impact | Yes | None |
| Can be disabled | By user | No |
| Kill switch reliability | App-dependent | Hardware-level |
| DNS leak protection | Varies | Guaranteed |
| DPI bypass | Some apps | AmneziaWG |
| Setup complexity | Low | Medium |
| Ongoing maintenance | Per device | Centralized |

---

## Supported VPN Providers

Any provider offering WireGuard configurations works. Tested with:

- **Mullvad** — Privacy-focused, no account, accepts cash
- **IVPN** — Strong privacy policy, multi-hop
- **ProtonVPN** — Swiss jurisdiction, Secure Core
- **AirVPN** — Port forwarding, flexible
- **Windscribe** — Good free tier for testing

For **AmneziaWG obfuscation**, you need a provider that supplies AWG configs with obfuscation parameters, or use a provider's standard WireGuard config with regular WireGuard.

---

## Hardware Recommendations

### Budget (~$50-80)
- Raspberry Pi 4 (2GB+) with USB Ethernet adapter
- GL.iNet travel routers (some run OpenWrt)

### Recommended (~$100-150)
- Raspberry Pi 5 with USB 3.0 Ethernet
- Zimaboard or similar x86 SBC

### Performance (~$150-300)
- Mini PC with dual NICs (Intel N100 systems)
- Protectli Vault or similar

### Homelab / Enterprise
- Virtual machine on existing hypervisor (Proxmox, ESXi, Hyper-V)
- Dedicated x86 firewall appliance

---

## Security Considerations

### What This Protects Against
- ISP traffic monitoring and logging
- Network-level ad tracking
- DNS hijacking and monitoring
- IP-based geolocation
- Traffic correlation (when combined with good OpSec)
- VPN blocking via DPI (with AmneziaWG)

### What This Doesn't Protect Against
- Browser fingerprinting
- Logged-in account tracking (Google, Facebook, etc.)
- Malware on your devices
- Physical access to your network
- Compromised VPN provider

### OpSec Recommendations
- Use privacy-focused browsers (Firefox, Brave)
- Use privacy-respecting search engines
- Log out of tracking services when not needed
- Consider compartmentalized identities
- Keep devices updated

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes
4. Submit a pull request

Areas where help is appreciated:
- Additional hardware guides
- Localization
- Performance optimizations
- Docker improvements

---

## License

MIT License — See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [OpenWrt Project](https://openwrt.org/) — The foundation
- [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-tools) — DPI bypass
- [AdGuard Home](https://adguard.com/adguard-home.html) — DNS filtering
- [WireGuard](https://www.wireguard.com/) — Modern VPN protocol

---

## FAQ

**Q: Will this slow down my internet?**
A: Minimal impact. WireGuard is extremely efficient. Most users see <5% speed reduction. The main factor is your VPN provider's server quality.

**Q: Can I still access local network devices?**
A: Yes. LAN traffic stays local and doesn't go through the VPN.

**Q: What if the privacy router fails?**
A: Your network loses internet until it's fixed or bypassed. This is a feature, not a bug — it ensures no unprotected traffic leaks.

**Q: Can I exclude certain devices from the VPN?**
A: Yes, with additional configuration. You can create firewall rules to route specific IPs directly to WAN. See [CONFIGURATION.md](docs/CONFIGURATION.md).

**Q: Does this work with IPv6?**
A: IPv6 is disabled to prevent leaks. Most VPN providers don't properly support IPv6 yet.

**Q: Can my ISP see I'm using a VPN?**
A: With standard WireGuard, they can see VPN-like traffic. With AmneziaWG obfuscation, the traffic appears as random noise.

---

*Protect your entire network. Set it and forget it.*
