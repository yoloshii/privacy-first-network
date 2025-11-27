# Troubleshooting Guide

Common issues and their solutions.

## Table of Contents

1. [VPN Issues](#vpn-issues)
2. [DNS Issues](#dns-issues)
3. [Connectivity Issues](#connectivity-issues)
4. [Kill Switch Issues](#kill-switch-issues)
5. [Performance Issues](#performance-issues)
6. [Diagnostic Commands](#diagnostic-commands)

---

## VPN Issues

### VPN Won't Connect

**Symptoms:**
- `awg0` interface exists but no handshake
- No traffic through tunnel
- `amneziawg show awg0` shows no recent handshake

**Diagnosis:**

```bash
# Check interface exists
ip link show awg0

# Check WireGuard status
amneziawg show awg0

# Look for handshake time
# "latest handshake: X seconds ago" = working
# No handshake = problem
```

**Solutions:**

1. **Endpoint route missing:**
   ```bash
   # Check if endpoint is routable
   ip route get VPN_SERVER_IP

   # Should show: via WAN_GATEWAY dev eth0
   # If shows: dev awg0 = WRONG (infinite loop)

   # Fix: Add endpoint route
   ip route add VPN_SERVER_IP via WAN_GATEWAY
   ```

2. **Wrong AWG parameters:**
   ```bash
   # AWG params MUST match server exactly
   # Check your provider's documentation
   # Common: Jc, Jmin, Jmax, S1, S2, H1-H4
   ```

3. **Firewall blocking UDP:**
   ```bash
   # Check if WAN allows outbound UDP 51820
   nft list ruleset | grep 51820

   # Most ISPs don't block outbound UDP
   # If blocked, try port 443 or 80 on VPN server
   ```

4. **Clock skew:**
   ```bash
   # WireGuard handshake uses timestamps
   # Check system time
   date

   # Sync time
   ntpd -q -p pool.ntp.org
   ```

### VPN Connects But No Internet

**Symptoms:**
- Handshake successful
- `ping 1.1.1.1` fails through awg0
- `curl am.i.mullvad.net` times out

**Diagnosis:**

```bash
# Check routing
ip route

# Should see:
# default dev awg0  ← All traffic via VPN
# VPN_IP via GATEWAY dev eth0  ← Endpoint reachable
```

**Solutions:**

1. **Missing default route:**
   ```bash
   ip route del default 2>/dev/null
   ip route add default dev awg0
   ```

2. **NAT not enabled:**
   ```bash
   # Check masquerade on VPN zone
   uci show firewall | grep vpn

   # Should have: masq='1'
   uci set firewall.vpn.masq='1'
   uci commit firewall
   /etc/init.d/firewall restart
   ```

3. **AllowedIPs too restrictive:**
   ```bash
   # In awg0.conf, Peer section should have:
   AllowedIPs = 0.0.0.0/0, ::/0
   # Not just the server's IP
   ```

### VPN Keeps Disconnecting

**Symptoms:**
- Works initially, then dies
- Watchdog keeps restarting tunnel

**Solutions:**

1. **PersistentKeepalive missing:**
   ```ini
   # Add to [Peer] section
   PersistentKeepalive = 25
   ```

2. **ISP throttling:**
   - Try different VPN server
   - Try different port (if provider supports)
   - Increase Jc value for more obfuscation

3. **Memory issues:**
   ```bash
   free -m
   # If low on memory, reduce AdGuard cache size
   ```

---

## DNS Issues

### DNS Not Resolving

**Symptoms:**
- `nslookup google.com` fails
- Websites don't load by name
- IPs work (`ping 1.1.1.1` succeeds)

**Diagnosis:**

```bash
# Check what DNS client is using
cat /etc/resolv.conf

# Test AdGuard directly
nslookup google.com 192.168.1.5

# Test upstream
nslookup google.com 100.64.0.4
```

**Solutions:**

1. **AdGuard not running:**
   ```bash
   # Check service status
   AdGuardHome -s status

   # Restart if needed
   AdGuardHome -s restart
   ```

2. **Wrong DNS pushed via DHCP:**
   ```bash
   # Check DHCP options
   uci show dhcp | grep dhcp_option

   # Fix: Push AdGuard IP
   uci delete dhcp.lan.dhcp_option
   uci add_list dhcp.lan.dhcp_option='6,192.168.1.5'
   uci commit dhcp
   /etc/init.d/dnsmasq restart

   # Clients need to renew DHCP lease
   ```

3. **AdGuard upstream unreachable:**
   ```bash
   # Test DoH upstream
   curl -v 'https://adblock.dns.mullvad.net/dns-query?dns=AAABAAABAAAAAAAA'

   # If fails, VPN might be down
   # Check VPN first
   ```

### Ads Still Showing

**Symptoms:**
- Some ads getting through
- AdGuard dashboard shows queries but no blocks

**Solutions:**

1. **Add more blocklists:**
   - AdGuard UI → Filters → DNS blocklists
   - Add: EasyList, EasyPrivacy, StevenBlack hosts

2. **Device using hardcoded DNS:**
   ```bash
   # Some devices ignore DHCP DNS (Chromecast, etc.)
   # Block DNS to external servers

   # In firewall, add rule:
   uci add firewall rule
   uci set firewall.@rule[-1].name='Block-External-DNS'
   uci set firewall.@rule[-1].src='lan'
   uci set firewall.@rule[-1].dest='vpn'
   uci set firewall.@rule[-1].dest_port='53'
   uci set firewall.@rule[-1].proto='tcp udp'
   uci set firewall.@rule[-1].target='REJECT'
   uci commit firewall
   /etc/init.d/firewall restart
   ```

3. **Browser DNS-over-HTTPS:**
   - Browsers like Firefox have built-in DoH
   - Disable in browser settings
   - Or use AdGuard's DNS rewrites to block DoH endpoints

### DNS Leaking

**Symptoms:**
- DNS leak test shows ISP DNS
- ipleak.net shows wrong DNS servers

**Solutions:**

1. **Router using ISP DNS:**
   ```bash
   # Check router's DNS
   uci show network | grep dns

   # Fix: Set to VPN provider DNS
   uci set network.lan.dns='100.64.0.4'
   uci commit network
   /etc/init.d/network restart
   ```

2. **IPv6 DNS leak:**
   ```bash
   # Disable IPv6 completely
   uci set network.wan.ipv6='0'
   uci set network.lan.ipv6='0'
   echo 'net.ipv6.conf.all.disable_ipv6=1' >> /etc/sysctl.conf
   sysctl -p
   ```

---

## Connectivity Issues

### No Internet at All

**Diagnosis flowchart:**

```
Can ping router (192.168.1.1)?
├── No → Check physical connection, DHCP
└── Yes
    └── Can ping VPN internal IP?
        ├── No → VPN tunnel down
        └── Yes
            └── Can ping 1.1.1.1?
                ├── No → Routing issue
                └── Yes
                    └── Can resolve DNS?
                        ├── No → DNS issue
                        └── Yes → Should work!
```

### LAN Devices Can't Reach Each Other

**Symptoms:**
- Can't ping other LAN devices
- Can't access LAN services (NAS, printer)

**Solutions:**

1. **Bridge misconfiguration:**
   ```bash
   # Check bridge
   brctl show

   # All LAN ports should be in br-lan
   ```

2. **Firewall blocking LAN:**
   ```bash
   # LAN zone should allow all
   uci show firewall | grep -A4 "zone\[0\]"
   # input=ACCEPT, forward=ACCEPT
   ```

### Can't Access Router Web UI

**Symptoms:**
- SSH works
- HTTP/HTTPS doesn't load

**Solutions:**

1. **Check service running:**
   ```bash
   netstat -tlnp | grep uhttpd
   ```

2. **HTTPS redirect but no certificate:**
   ```bash
   # Install SSL
   opkg install luci-ssl

   # Or disable redirect
   uci set uhttpd.main.redirect_https='0'
   uci commit uhttpd
   /etc/init.d/uhttpd restart
   ```

3. **Wrong port:**
   ```bash
   # Check listen port
   uci show uhttpd | grep listen

   # Default: 80 (HTTP), 443 (HTTPS)
   # If changed, use correct port in URL
   ```

---

## Kill Switch Issues

### Kill Switch Not Working

**Symptoms:**
- Internet works when VPN is down
- Real IP exposed when VPN fails

**Diagnosis:**

```bash
# Bring VPN down
ip link set awg0 down

# Try to reach internet
curl ifconfig.me
# Should fail/timeout, NOT show your real IP

# If it shows your IP, kill switch is broken
```

**Solutions:**

1. **LAN→WAN forwarding exists:**
   ```bash
   # Check for unwanted forwarding
   uci show firewall | grep forwarding

   # Should only have lan→vpn
   # Remove any lan→wan
   uci delete firewall.@forwarding[X]  # Replace X with index
   uci commit firewall
   /etc/init.d/firewall restart
   ```

2. **Default route pointing to WAN:**
   ```bash
   # Check routes
   ip route

   # If you see: default via WAN_GATEWAY dev eth0
   # That's wrong when VPN should be default

   # Fix routing in startup scripts
   ```

3. **Masquerade on WAN zone:**
   ```bash
   # WAN zone should NOT have masq if you don't want fallback
   uci show firewall | grep wan

   # Actually, masq on WAN is fine - the forwarding rules prevent it
   # The key is: NO lan→wan forwarding rule
   ```

### Can't Access Anything When VPN Down (Even LAN)

**Symptoms:**
- Kill switch too aggressive
- Can't even SSH to router when VPN fails

**This is actually WRONG behavior.** LAN access should always work.

**Solutions:**

1. **LAN zone input not ACCEPT:**
   ```bash
   uci show firewall | grep -A4 zone.*lan

   # Must have: input='ACCEPT'
   uci set firewall.@zone[0].input='ACCEPT'
   uci commit firewall
   /etc/init.d/firewall restart
   ```

2. **Default policy too strict:**
   ```bash
   # Default input should be REJECT (not DROP)
   # DROP silently fails, REJECT sends response
   uci set firewall.@defaults[0].input='REJECT'
   ```

---

## Performance Issues

### Slow Speeds

**Expected overhead:**
- VPN: 5-15% reduction from encryption
- AmneziaWG: Additional 5% from obfuscation
- Geographic distance: +20-100ms latency

**Diagnosis:**

```bash
# Test without VPN (temporarily)
ip link set awg0 down
speedtest-cli

# Test with VPN
ip link set awg0 up
speedtest-cli

# Compare results
```

**Solutions:**

1. **Choose closer VPN server:**
   - Use server in your region
   - Less distance = less latency

2. **Reduce AWG overhead:**
   ```ini
   # Lower Jc (fewer junk packets)
   Jc = 2

   # Smaller junk size
   Jmin = 20
   Jmax = 40
   ```

3. **MTU optimization:**
   ```bash
   # Find optimal MTU
   ping -c 5 -M do -s 1400 1.1.1.1

   # Reduce if fragmentation
   ip link set awg0 mtu 1380
   ```

4. **Hardware crypto:**
   ```bash
   # Check if available
   grep -m1 'aes\|neon' /proc/cpuinfo

   # Modern ARM/x86 has hardware acceleration
   ```

### High Latency

**Normal latency ranges:**
- Same country: 20-50ms
- Same continent: 50-150ms
- Intercontinental: 150-300ms

**Solutions:**

1. **DNS latency:**
   ```bash
   # Test DNS response time
   time nslookup google.com

   # If slow, check AdGuard upstream
   # Use closer DNS server
   ```

2. **Bufferbloat:**
   ```bash
   # Install SQM (Smart Queue Management)
   opkg install luci-app-sqm

   # Configure for your connection speed
   ```

---

## Diagnostic Commands

### System Status

```bash
# System overview
uptime
free -m
df -h

# Network interfaces
ip -br addr
ip -br link

# Routing table
ip route

# Active connections
netstat -tn
```

### VPN Status

```bash
# WireGuard status
amneziawg show awg0

# Check handshake time
amneziawg show awg0 | grep 'latest handshake'

# Traffic statistics
amneziawg show awg0 | grep 'transfer'

# Interface details
ip addr show awg0
```

### Firewall Status

```bash
# UCI config
uci show firewall

# Active nftables rules
nft list ruleset

# Connection tracking
cat /proc/net/nf_conntrack | wc -l
```

### DNS Status

```bash
# Test resolution
nslookup google.com
dig google.com @192.168.1.5

# AdGuard status
AdGuardHome -s status

# AdGuard logs
tail -f /opt/AdGuardHome/data/querylog.json
```

### Logs

```bash
# System log
logread

# Kernel messages
dmesg | tail -50

# Watchdog log
tail -f /var/log/awg-watchdog.log

# Firewall log (if enabled)
logread | grep firewall
```

### Network Testing

```bash
# Ping test
ping -c 5 1.1.1.1

# Ping through VPN interface
ping -c 5 -I awg0 1.1.1.1

# Check external IP
curl ifconfig.me

# Full VPN check
curl https://am.i.mullvad.net/connected

# DNS leak test
curl https://bash.ws/dnsleak/test/
```

---

## Getting Help

If you're still stuck:

1. Collect diagnostic output:
   ```bash
   ip route
   amneziawg show awg0
   uci show firewall
   logread | tail -100
   ```

2. Check logs for errors
3. Search issues on GitHub
4. Open new issue with diagnostics
