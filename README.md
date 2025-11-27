# Privacy Router Stack

**Whole-home VPN router with hardware kill switch** - Protect every device on your network with OpenWrt, WireGuard, and AmneziaWG. No apps required.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05+-00B5E2.svg)](https://openwrt.org/)
[![WireGuard](https://img.shields.io/badge/WireGuard-VPN-88171A.svg)](https://www.wireguard.com/)

> **🤖 Using an AI coding agent?** Give it access to this entire repo and read [AGENTS.md](AGENTS.md) for guided deployment. Supports Claude, GPT, Gemini, and other frontier models.

---

## TL;DR

Turn a Raspberry Pi or mini PC into a VPN gateway that protects your entire home network:

- ✅ **All devices protected** - Smart TVs, consoles, IoT, phones, laptops, guests
- ✅ **Hardware kill switch** - Firewall-level failsafe, not software
- ✅ **DPI bypass** - AmneziaWG defeats VPN blocking in restrictive networks
- ✅ **DNS encryption** - AdGuard Home with DNS-over-HTTPS
- ✅ **Auto-recovery** - Watchdog restarts tunnel on failure
- ✅ **AI-deployable** - Full agent instructions included

**Works with:** Any WireGuard-compatible VPN provider (Mullvad, IVPN, AirVPN, etc.)

**AmneziaWG obfuscation:** Mullvad + custom params, AirVPN, or self-hosted Amnezia server

---

## Why Now? The Privacy Landscape Is Changing

**2025 is a turning point for online privacy:**

- **UK Online Safety Bill** - Age verification now required for adult content. Third-party services verify your identity and track what you access.
- **Australia Social Media Ban** - Age verification requirements taking effect December 2025. Platforms must verify user ages.
- **US State Laws** - Multiple states passing age verification bills for various content categories.
- **EU Digital Services Act** - Expanded platform accountability with data retention requirements.

**What this means for you:**
- Your ISP can see every site you visit
- Age verification services build profiles of your browsing
- Data retention laws store your history for years
- Per-device VPN apps don't protect smart TVs, consoles, or IoT devices

**This stack solves all of these problems** - every device on your network routes through an encrypted tunnel. No browsing history for your ISP. No identity verification per-site. No apps to install or forget to enable.

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

This privacy router sits between your modem and your existing router. **Every device** on your network automatically routes through the VPN - no apps, no configuration, no exceptions.

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

**Every device is protected:** Phones, tablets, laptops, smart TVs, gaming consoles, IoT devices, guests - everything.

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

When a VPN app crashes, loses connection, or during the moments between connection drops and reconnection, your traffic can leak to your ISP. App-based kill switches try to prevent this, but they operate at the application level - if the app itself crashes, the kill switch dies with it.

**This stack implements a hardware-level kill switch:**

```
Normal Operation:
  Device → Privacy Router → VPN Tunnel → Internet ✓

VPN Down (App-based kill switch):
  Device → [App crashed] → ISP sees traffic ✗

VPN Down (This stack):
  Device → Privacy Router → [No route exists] → Traffic blocked ✓
```

The kill switch is implemented in the **firewall and routing table**, not in software. If the VPN tunnel goes down, there is literally no route for traffic to take - it's not blocked by a rule that might fail, it simply has nowhere to go.

---

## Features

### Core Protection (Required)
- **Network-wide VPN** - All devices protected automatically
- **Hardware kill switch** - No traffic leaks, ever
- **IPv6 leak prevention** - IPv6 completely disabled

### Reliability (Required)
- **Automatic recovery** - Watchdog restarts tunnel on failure
- **Boot persistence** - VPN starts automatically on power-up
- **Connection monitoring** - Continuous health checks

### Optional Security Addons
- **AdGuard Home** - DNS-over-HTTPS encryption, ad/tracker blocking
- **BanIP** - Threat intelligence, malicious IP blocking
- **HTTPS for LuCI** - Encrypted admin interface

See [OPTIONAL_ADDONS.md](docs/OPTIONAL_ADDONS.md) for installation and configuration.

### Advanced (For Technical Users)
- **DPI bypass** - AmneziaWG obfuscation defeats deep packet inspection
- **Flexible deployment** - Dedicated hardware or VM
- **Full observability** - Detailed logging and diagnostics

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

Traffic from LAN can **only** go to the VPN zone. There is no forwarding rule from LAN to WAN. This isn't a "block" rule that could be bypassed - the route simply doesn't exist.

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

If your VPN works fine with regular WireGuard, you can use standard WireGuard instead - the architecture works with both.

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

> **Why not Docker?** This stack requires kernel-level kill switch guarantees, dual NIC management, and native routing - all of which are compromised by container networking. For containerized workloads that need VPN, consider a WireGuard sidecar pattern or [gluetun](https://github.com/qdm12/gluetun) instead.

---

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, components, security model |
| [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | Deep technical dive into every component |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Step-by-step installation guide |
| [CONFIGURATION.md](docs/CONFIGURATION.md) | Complete configuration reference |
| [OPTIONAL_ADDONS.md](docs/OPTIONAL_ADDONS.md) | AdGuard Home, BanIP, and other security addons |
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

## VPN Provider Compatibility

### Who This Stack Is For

This stack is designed for users in regions where privacy legislation is tightening:

| Region | Legislation | Impact |
|--------|-------------|--------|
| **UK** | Online Safety Bill (2025) | Age verification required for adult content; third-party ID services track access |
| **Australia** | Social Media Age Verification (Dec 2025) | Under-16 ban with verification requirements |
| **EU** | Digital Services Act | Platform accountability with data retention |
| **US States** | Various age verification bills | State-level ID requirements expanding |

**Common privacy concerns this stack addresses:**
- ISPs required to log browsing history
- Third-party age verification services collecting identity data
- Data retention laws mandating surveillance
- Privacy-invasive legislation expanding

A network-level VPN means no per-device verification, no browsing history for your ISP, and no identity disclosure to third-party verification services.

If you're in a region where VPNs are actively blocked or criminalized, see [High-Censorship Environments](#high-censorship-environments) below.

### Recommended: Mullvad VPN

**[Mullvad VPN](https://mullvad.net)** is strongly recommended. This entire stack was developed, tested, and deployed with Mullvad.

**Why Mullvad:**
- **No customer records** - They keep nothing. No logs, no account data, no email.
- **Anonymous payment** - Cash, cryptocurrency, bank transfer. No identity required.
- **WireGuard native** - Fast, modern protocol with excellent performance.
- **Proven track record** - Survived law enforcement audits with no data to hand over.
- **Transparent** - Open source apps, regular security audits, clear policies.

### Alternative WireGuard Providers

If you prefer a different provider, any WireGuard-compatible VPN works with this stack:

| Provider | Privacy | Notes |
|----------|---------|-------|
| **[IVPN](https://ivpn.net)** | No logs, open source | Good Mullvad alternative |
| **[AirVPN](https://airvpn.org)** | No logs, port forwarding | Community AWG params available |
| **[ProtonVPN](https://protonvpn.com)** | No logs (paid plans) | Free tier available |

> **Note:** These providers use standard WireGuard. For basic privacy protection, this is sufficient. Use this stack with standard WireGuard configs - AmneziaWG obfuscation is optional.

### AmneziaWG Obfuscation (Optional)

AmneziaWG adds traffic obfuscation to defeat deep packet inspection. **Most users don't need this** - it's for situations where:
- Your ISP throttles or blocks VPN traffic
- Network administrators block WireGuard
- You need extra protection against traffic analysis

| Option | Setup | Best For |
|--------|-------|----------|
| **Mullvad + AWG params** | Use included example params | Most users needing obfuscation |
| **AirVPN** | Community-discovered params | AirVPN subscribers |
| **Self-hosted Amnezia** | Run your own server | Maximum control |

**Mullvad-specific example configs included:**
- `openwrt/amneziawg/mullvad-awg0.conf.example` - Tunnel config with obfuscation
- `adguard/mullvad-AdGuardHome.yaml.example` - DNS using Mullvad DoH

### High-Censorship Environments

**If you're in a region where VPNs are actively blocked or criminalized**, WireGuard and AmneziaWG may not be sufficient. These environments require more advanced obfuscation:

| Protocol | Description |
|----------|-------------|
| **VLESS + Reality** | Traffic appears as normal HTTPS to major websites |
| **XRay** | Advanced proxy with multiple obfuscation modes |
| **ShadowSocks** | Encrypted proxy designed for restricted network environments |
| **Tor + Bridges** | Anonymity network with pluggable transports |

**For agents:** If your user is in a high-censorship environment, use deep research to find current best practices:

```
Search: "VLESS Reality setup 2025"
Search: "XRay traffic obfuscation setup 2025"
```

> **This stack focuses on WireGuard/AmneziaWG.** For VLESS, XRay, or other advanced protocols, users should research dedicated solutions or consider running [Amnezia VPN](https://amnezia.org) which supports multiple protocols including XRay.

---

## Hardware Recommendations

> **Minimum Requirements:** 1GB RAM, dual network interfaces (built-in + USB), OpenWrt support. Recommended: 2GB+ RAM for AdGuard Home DNS filtering.

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

## AI-Assisted Setup

For complex deployments or troubleshooting, give an AI coding agent access to this **entire repository** plus SSH access to your router.

**Recommended:** This stack was developed, tested, and deployed using **Claude Opus 4.5** via [Claude Code](https://claude.com/claude-code). For best results, use a capable frontier model that can execute shell commands and understand network configuration:

- **Claude Opus 4.5 / Sonnet 4.5** (Anthropic) - Used for this implementation
- **GPT-5.1** (OpenAI)
- **Gemini 3** (Google)

**What the agent can do:**
- **Network audit** - Probe your current setup and identify requirements
- **Guided configuration** - Generate configs with your specific IPs, keys, and preferences
- **Automated troubleshooting** - Diagnose routing, firewall, and DNS issues in real-time
- **Scripted deployment** - Execute installation steps with your approval

**Quick start:**
1. Clone this repo or give agent GitHub access
2. Point agent to **[AGENTS.md](AGENTS.md)** - contains the full operational framework
3. Provide SSH credentials to your target device
4. Let agent audit, plan, and guide you through deployment

The agent instructions include diagnostic commands, validation tests, error recovery procedures, and safety rules. All configs in this repo are parameterized and agent-friendly.

---

## Related Projects

This stack builds on excellent open-source work:

| Project | Description |
|---------|-------------|
| [amnezia-vpn/amneziawg-linux-kernel-module](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module) | AmneziaWG kernel module |
| [amnezia-vpn/amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools) | AmneziaWG userspace tools |
| [Slava-Shchipunov/awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt) | Pre-built AmneziaWG packages for OpenWrt |
| [wgtunnel/wgtunnel](https://github.com/wgtunnel/wgtunnel) | WireGuard tunnel management |

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

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [OpenWrt Project](https://openwrt.org/) - The foundation
- [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-tools) - DPI bypass
- [AdGuard Home](https://adguard.com/adguard-home.html) - DNS filtering
- [WireGuard](https://www.wireguard.com/) - Modern VPN protocol

---

## FAQ

**Q: Will this slow down my internet?**
A: Minimal impact. WireGuard is extremely efficient. Most users see <5% speed reduction. The main factor is your VPN provider's server quality.

**Q: Can I still access local network devices?**
A: Yes. LAN traffic stays local and doesn't go through the VPN.

**Q: What if the privacy router fails?**
A: Your network loses internet until it's fixed or bypassed. This is a feature, not a bug - it ensures no unprotected traffic leaks.

**Q: Can I exclude certain devices from the VPN?**
A: Yes, with additional configuration. You can create firewall rules to route specific IPs directly to WAN. See [CONFIGURATION.md](docs/CONFIGURATION.md).

**Q: Does this work with IPv6?**
A: IPv6 is disabled to prevent leaks. Most VPN providers don't properly support IPv6 yet.

**Q: Can my ISP see I'm using a VPN?**
A: With standard WireGuard, they can see VPN-like traffic. With AmneziaWG obfuscation, the traffic appears as random noise.

**Q: How does this help with age verification privacy concerns?**
A: A VPN routes your traffic through an encrypted tunnel, preventing your ISP from logging which sites you visit. This is a **privacy tool** - it stops third-party age verification services from correlating your browsing activity across sites or building behavioral profiles. Your actual age verification with platforms remains between you and that platform, not shared with ISPs or data brokers. For specific compliance questions, consult local regulations.

**Q: Will this work after the Australia social media ban takes effect?**
A: This stack protects your network traffic from ISP logging and provides privacy for all devices. The December 2025 Australian legislation primarily affects platform-side verification. A VPN ensures your ISP cannot see which sites you visit, regardless of platform-level requirements.

**Q: Is this legal?**
A: VPN use is legal in most Western countries including the UK, Australia, US, and EU. This stack is a privacy tool similar to HTTPS - it encrypts your traffic. Using a VPN to access content available in your region is generally legal. Always check your local laws.

---

*Protect your entire network. Set it and forget it.*
