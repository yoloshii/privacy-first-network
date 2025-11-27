# Deployment Guide

Step-by-step instructions for deploying the privacy router stack.

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 1 core | 2+ cores |
| RAM | 512 MB | 1 GB |
| Storage | 1 GB | 4+ GB |
| Network | 2 interfaces | 2 interfaces |

**Supported Platforms:**
- Raspberry Pi 4/5
- x86/x64 mini PC
- Virtual machine (any hypervisor)

### Software Requirements

- OpenWrt 23.05 or later (or compatible Linux)
- AmneziaWG packages (kmod-amneziawg, amneziawg-tools)
- AdGuard Home (latest)

### Network Requirements

- Internet connection via modem/ONT
- Existing WiFi router (to convert to AP mode)
- VPN provider account with WireGuard/AmneziaWG support

---

## Deployment Options

Choose your deployment path:

| Option | Difficulty | Best For |
|--------|------------|----------|
| [A. Dedicated Hardware](#option-a-dedicated-hardware) | Easy | **Recommended** - Most users, best reliability |
| [B. Virtual Machine](#option-b-virtual-machine) | Medium | Homelab, enterprise, existing hypervisors |
| [C. Docker Container](#option-c-docker-container-optional) | Advanced | Optional - for users who prefer containers |

> **Recommendation:** Options A and B are recommended. Option C (Docker) is entirely optional and provided only as a convenience for advanced users who prefer containers.

---

## Option A: Dedicated Hardware

### A1. Install OpenWrt

**For Raspberry Pi:**

```bash
# Download OpenWrt image for your device
# https://openwrt.org/toh/raspberry_pi_foundation/raspberry_pi

# Write to SD card (Linux/macOS)
sudo dd if=openwrt-*.img of=/dev/sdX bs=4M status=progress

# Boot the Pi, connect via ethernet
ssh root@192.168.1.1
```

**For x86 Mini PC:**

```bash
# Download x86/64 image from openwrt.org
# Write to USB/SSD and boot
```

### A2. Configure Network Interfaces

Edit `/etc/config/network`:

```bash
uci set network.lan=interface
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.1.1'  # Your gateway IP
uci set network.lan.netmask='255.255.255.0'

uci set network.wan=interface
uci set network.wan.device='eth0'  # Your WAN interface
uci set network.wan.proto='dhcp'

uci commit network
```

### A3. Install AmneziaWG

**Method 1: Pre-built packages (recommended)**

```bash
# Check your OpenWrt version
cat /etc/openwrt_release

# Download packages from:
# https://github.com/amnezia-vpn/amneziawg-openwrt/releases

# Install dependencies
opkg update
opkg install kmod-crypto-lib-chacha20 kmod-crypto-lib-chacha20poly1305 \
             kmod-crypto-lib-curve25519 kmod-udptunnel4 kmod-udptunnel6

# Install AmneziaWG (adjust filename for your version)
opkg install /tmp/kmod-amneziawg_*.ipk
opkg install /tmp/amneziawg-tools_*.ipk
```

**Method 2: Build from source**

See: https://github.com/amnezia-vpn/amneziawg-openwrt

### A4. Configure VPN Tunnel

Create config directory:

```bash
mkdir -p /etc/amneziawg
```

Create `/etc/amneziawg/awg0.conf`:

```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY_HERE

# AmneziaWG obfuscation (get these from your VPN provider)
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
PublicKey = VPN_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = VPN_SERVER_IP:51820
PersistentKeepalive = 25
```

Set permissions:

```bash
chmod 600 /etc/amneziawg/awg0.conf
```

### A5. Configure Firewall

Create VPN zone and kill switch:

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

# Allow LAN to VPN forwarding ONLY (kill switch)
uci set firewall.lan_vpn=forwarding
uci set firewall.lan_vpn.src='lan'
uci set firewall.lan_vpn.dest='vpn'

# Ensure NO lan->wan forwarding exists (verify kill switch)
# This should already be the default - no lan->wan rule

uci commit firewall
```

### A6. Install Startup Scripts

Copy from `scripts/` directory:

```bash
# Copy watchdog script
cp scripts/awg-watchdog.sh /etc/awg-watchdog.sh
chmod +x /etc/awg-watchdog.sh

# Edit watchdog with your values (REQUIRED):
vi /etc/awg-watchdog.sh
# Set: VPN_IP, ENDPOINT_IP (find these in your VPN provider config)

# Copy hotplug script (auto-starts VPN on WAN up)
mkdir -p /etc/hotplug.d/iface
cp scripts/99-awg-hotplug /etc/hotplug.d/iface/99-awg
chmod +x /etc/hotplug.d/iface/99-awg

# Edit hotplug script with same values:
vi /etc/hotplug.d/iface/99-awg
# Set: VPN_IP, ENDPOINT_IP
```

**For OpenWrt (init.d):**

```bash
# Install init script for boot persistence
cp scripts/awg-watchdog.init /etc/init.d/awg-watchdog
chmod +x /etc/init.d/awg-watchdog

# Enable at boot
/etc/init.d/awg-watchdog enable

# Start now
/etc/init.d/awg-watchdog start

# Verify running
ps | grep awg-watchdog
```

**For standard Linux (systemd):**

```bash
# Copy systemd service files
sudo cp scripts/awg-watchdog.service /etc/systemd/system/
sudo cp scripts/adguardhome.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start services
sudo systemctl enable awg-watchdog adguardhome
sudo systemctl start awg-watchdog adguardhome

# Verify running
sudo systemctl status awg-watchdog
sudo systemctl status adguardhome
```

**Configuration values you need:**
| Variable | Description | Example (Mullvad) |
|----------|-------------|-------------------|
| `VPN_IP` | Your VPN internal IP (from provider config) | `10.64.123.45/32` |
| `ENDPOINT_IP` | VPN server IP address | `185.213.154.68` |
| `WAN_GATEWAY` | Usually "auto" (auto-detected) | `auto` or `192.168.1.1` |

### A7. Test VPN Manually

```bash
# Create interface
ip link add dev awg0 type amneziawg

# Apply config
amneziawg setconf awg0 /etc/amneziawg/awg0.conf

# Add address (use your VPN internal IP)
ip address add 10.x.x.x/32 dev awg0

# Bring up
ip link set up dev awg0

# Add routes (use your VPN server IP and WAN gateway)
ip route add VPN_SERVER_IP via WAN_GATEWAY
ip route del default 2>/dev/null
ip route add default dev awg0

# Test
curl https://am.i.mullvad.net/ip
# Should show VPN exit IP, not your real IP
```

### A8. Deploy AdGuard Home

**Option 1: On OpenWrt (limited resources)**

```bash
# Download AdGuard Home binary
cd /tmp
wget https://static.adguard.com/adguardhome/release/AdGuardHome_linux_arm64.tar.gz
tar xzf AdGuardHome_linux_arm64.tar.gz
mv AdGuardHome/AdGuardHome /usr/bin/

# Run setup
AdGuardHome -s install

# Access web UI at http://router-ip:3000
```

**Option 2: Separate device/container (recommended)**

Deploy AdGuard Home on a separate LXC container, VM, or device:

```bash
# On Debian/Ubuntu
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

# Configure at http://adguard-ip:3000
```

### A9. Configure DHCP to Push AdGuard DNS

On OpenWrt:

```bash
# Push AdGuard as DNS server to clients
uci add_list dhcp.lan.dhcp_option='6,ADGUARD_IP'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

### A10. Configure AdGuard Upstream DNS

In AdGuard web UI (Settings → DNS Settings → Upstream DNS):

```
# Use DNS-over-HTTPS to your VPN provider
https://adblock.dns.mullvad.net/dns-query

# Or use VPN provider's plain DNS (if inside VPN tunnel)
100.64.0.4
```

Enable:
- DNSSEC
- Parallel requests
- Cache enabled

### A11. Security Hardening

```bash
# Disable IPv6 (prevents leaks)
uci set network.wan.ipv6='0'
uci set network.lan.ipv6='0'
uci delete network.wan6 2>/dev/null
uci commit network

# Disable IPv6 in kernel
echo 'net.ipv6.conf.all.disable_ipv6=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.default.disable_ipv6=1' >> /etc/sysctl.conf
sysctl -p

# Restrict SSH to LAN only
uci set dropbear.@dropbear[0].Interface='lan'
uci commit dropbear
/etc/init.d/dropbear restart

# Enable HTTPS for web UI (optional)
opkg update
opkg install luci-ssl
uci set uhttpd.main.redirect_https='1'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

### A12. Final Cutover

1. **Set existing router to AP mode**
   - Disable DHCP
   - Disable routing/NAT
   - Set to bridge mode
   - Assign static IP (e.g., 192.168.1.4)

2. **Connect cables**
   - Modem → OpenWrt WAN port
   - OpenWrt LAN port → WiFi AP

3. **Verify**
   ```bash
   # Check VPN
   curl https://am.i.mullvad.net/ip

   # Check DNS (should return 0.0.0.0)
   nslookup doubleclick.net

   # Check kill switch (disconnect VPN, verify no internet)
   ip link set awg0 down
   curl google.com  # Should fail
   ip link set awg0 up
   ```

---

## Option B: Virtual Machine

For homelab users with existing hypervisors (Proxmox, ESXi, Hyper-V, etc.).

### B1. Create OpenWrt VM

**General requirements:**
- 512MB+ RAM, 1-2 vCPUs
- Two virtual network interfaces (WAN and LAN)
- Download OpenWrt x86/64 image from openwrt.org

**Network configuration:**
- NIC 1 → Bridge to WAN network (connected to modem)
- NIC 2 → Bridge to LAN network (connected to your devices)

**Steps:**
1. Download OpenWrt x86/64 combined image
2. Create VM with 2 NICs bridged appropriately
3. Import/attach the OpenWrt disk image
4. Boot and continue from [A2](#a2-configure-network-interfaces)

### B2. Deploy AdGuard

Deploy AdGuard Home in a separate VM or container on the same hypervisor:

```bash
# On Debian/Ubuntu VM or container
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
```

Ensure the AdGuard VM/container is on the LAN bridge so it can serve DNS to clients.

### B3. Continue Setup

Continue from [A4](#a4-configure-vpn-tunnel) onwards - the configuration is identical to dedicated hardware once OpenWrt is running.

---

## Option C: Docker Container (Optional)

> **This is entirely optional** - provided for users who prefer Docker. Options A and B are the recommended deployment methods. You do not need Docker to use this privacy router.

> **For advanced users** familiar with macvlan networking, iptables, and container troubleshooting. If you're using an AI assistant (Claude, GPT, etc.), give it access to the `docker/` folder - the AI can guide you through setup even if Docker is unfamiliar.

For users with an existing Docker host who want a container-based deployment with macvlan networking.

### C1. Overview

The Docker deployment provides:
- **AmneziaWG VPN client** with kill switch
- **AdGuard Home** for DNS filtering
- **macvlan networking** for LAN gateway mode
- **Auto-recovery watchdog** and health checks
- **Comprehensive test suite** (10 tests including kill switch verification)

```
┌────────────────────────────────────────────────────┐
│              Docker Host (Linux)                   │
│  ┌──────────────────────────────────────────────┐  │
│  │         privacy-router container             │  │
│  │   AmneziaWG + AdGuard Home + Kill Switch     │  │
│  └──────────────────┬───────────────────────────┘  │
│                     │ macvlan (192.168.1.250)      │
└─────────────────────┼──────────────────────────────┘
                      │
           LAN: 192.168.1.0/24
```

### C2. Prerequisites

- Docker Engine 24.0+ with Compose V2
- Linux host with kernel 5.6+ (for WireGuard)
- LAN interface available for macvlan
- VPN subscription with WireGuard/AmneziaWG support

### C3. Quick Start

```bash
cd docker/

# Copy templates
cp .env.example .env
cp config/awg0.conf.example config/awg0.conf

# Edit with your values
nano .env                    # Set VPN_IP, VPN_ENDPOINT_IP, network config
nano config/awg0.conf        # Set PrivateKey, PublicKey

# Deploy
docker compose up -d

# Verify (quick check)
docker exec privacy-router /opt/scripts/quick-test.sh

# Full validation (includes kill switch test)
docker exec privacy-router /opt/scripts/test-suite.sh
```

### C4. Configure LAN Clients

Point devices to use the container as gateway and DNS:

| Setting | Value |
|---------|-------|
| Gateway | 192.168.1.250 (CONTAINER_LAN_IP) |
| DNS | 192.168.1.250 |

Or configure your router's DHCP to distribute these settings.

### C5. Full Documentation

See **[docker/README.md](../docker/README.md)** for:
- Complete configuration reference
- Environment variables
- Troubleshooting guide
- Security notes

---

## Post-Deployment Checklist

- [ ] VPN connected (check exit IP)
- [ ] Kill switch working (no internet when VPN down)
- [ ] DNS resolving through AdGuard
- [ ] Ads blocked (test doubleclick.net)
- [ ] IPv6 disabled
- [ ] SSH restricted to LAN
- [ ] All services start on boot
- [ ] Watchdog running
- [ ] Existing router in AP mode

## Next Steps

- [CONFIGURATION.md](CONFIGURATION.md) - Detailed config reference
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
