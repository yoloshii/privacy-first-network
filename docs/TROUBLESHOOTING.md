# Troubleshooting Guide

Common issues and their solutions.

## Table of Contents

1. [VPN Issues](#vpn-issues)
2. [DNS Issues](#dns-issues)
3. [Connectivity Issues](#connectivity-issues)
4. [Kill Switch Issues](#kill-switch-issues)
5. [VPN Bypass Issues](#vpn-bypass-issues)
6. [Performance Issues](#performance-issues)
7. [Diagnostic Commands](#diagnostic-commands)

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
- `curl ipinfo.io/ip` times out (or provider test like `am.i.mullvad.net`)

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

# Test upstream (use your VPN provider's DNS)
# Mullvad: 100.64.0.4 | IVPN: 10.0.254.1 | Proton: 10.2.0.1
nslookup google.com VPN_PROVIDER_DNS_IP
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
   # Test DoH upstream (use your provider's DoH URL)
   # Mullvad: adblock.dns.mullvad.net | IVPN: dns.ivpn.net | Proton: dns.protonvpn.net
   curl -v 'https://YOUR_PROVIDER_DOH_HOST/dns-query?dns=AAABAAABAAAAAAAA'

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
   # Mullvad: 100.64.0.4 | IVPN: 10.0.254.1 | Proton: 10.2.0.1
   uci set network.lan.dns='VPN_PROVIDER_DNS_IP'
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

## VPN Bypass Issues

### Bypass Device Still Going Through VPN

**Symptoms:**
- Added device to bypass list but still shows VPN IP
- `curl https://am.i.mullvad.net/connected` returns "You are connected"

**Diagnosis:**

```bash
# Check policy rules exist
ip rule show | grep 100
# Should list your bypass IPs

# Check table 100 has WAN route
ip route show table 100
# Should show: default via <WAN_GW> dev eth0

# Check firewall rule exists
uci show firewall | grep -A5 'Bypass'
```

**Solutions:**

1. **Policy rule missing:**
   ```bash
   # Add rule
   ip rule add from 192.168.1.X lookup 100 priority 100

   # Make persistent in /etc/rc.local
   ```

2. **Table 100 empty or wrong:**
   ```bash
   # Check if hotplug created table 100
   ip route show table 100

   # If empty, VPN tunnel may not be fully up
   # Restart VPN to recreate table 100
   ACTION=ifup INTERFACE=wan /etc/hotplug.d/iface/99-awg
   ```

3. **Firewall rule missing:**
   ```bash
   # Check for lan→wan ACCEPT for this IP
   uci show firewall | grep 'src_ip.*192.168.1.X'

   # Add if missing
   uci add firewall rule
   uci set firewall.@rule[-1].name='Bypass-DeviceName'
   uci set firewall.@rule[-1].src='lan'
   uci set firewall.@rule[-1].src_ip='192.168.1.X'
   uci set firewall.@rule[-1].dest='wan'
   uci set firewall.@rule[-1].target='ACCEPT'
   uci commit firewall
   /etc/init.d/firewall restart
   ```

4. **Wrong priority order:**
   ```bash
   ip rule show

   # Rules with lower priority number checked first
   # Bypass rules (priority 100) must come before main (32766)
   ```

### Bypass Device Has No Internet

**Symptoms:**
- Device was working, added to bypass, now no internet
- Can't reach anything from bypass device

**Diagnosis:**

```bash
# From bypass device (or via SSH proxying)
ping -c 3 1.1.1.1          # Test raw IP connectivity
ping -c 3 google.com        # Test DNS

# From router
traceroute -n 1.1.1.1 -s 192.168.1.X  # Trace from bypass IP
```

**Solutions:**

1. **WAN gateway changed (DHCP):**
   ```bash
   # Check current WAN gateway
   ip route show dev eth0 | grep default

   # Check table 100 gateway matches
   ip route show table 100

   # If different, recreate table 100
   ip route replace default via <NEW_GW> dev eth0 table 100
   ```

2. **Firewall blocking (no rule):**
   ```bash
   # Must have BOTH policy rule AND firewall rule
   # Check firewall
   iptables -L FORWARD -n -v | grep 192.168.1.X
   ```

3. **DNS not working for bypass device:**
   ```bash
   # If bypass device uses AdGuard for DNS, AdGuard must also bypass
   # OR bypass device uses external DNS directly

   # Check AdGuard is in bypass list
   ip rule show | grep 192.168.1.5

   # If not, add it
   ip rule add from 192.168.1.5 lookup 100 priority 100
   ```

### Table 100 Not Created

**Symptoms:**
- `ip route show table 100` returns nothing
- Bypass not working even though rules exist

**Diagnosis:**

```bash
# Check hotplug script exists and is executable
ls -la /etc/hotplug.d/iface/99-awg

# Check hotplug ran
logread | grep awg-hotplug

# Check VPN is up
ip link show awg0
```

**Solutions:**

1. **VPN not started:**
   ```bash
   # Table 100 is created when VPN starts
   # Start VPN manually
   ACTION=ifup INTERFACE=wan /etc/hotplug.d/iface/99-awg
   ```

2. **Hotplug script not executable:**
   ```bash
   chmod +x /etc/hotplug.d/iface/99-awg
   ```

3. **WAN gateway detection failed:**
   ```bash
   # Check gateway
   ip route show dev eth0 | grep default
   uci get network.wan.gateway

   # If empty, hotplug can't create table 100
   # Set static gateway or fix DHCP
   ```

### Bypass Device Loses Internet When VPN Restarts

**Symptoms:**
- Bypass works until VPN reconnects
- After VPN restart, bypass stops working

**Solutions:**

1. **Table 100 recreated without WAN route:**
   ```bash
   # Check table 100 after VPN restart
   ip route show table 100

   # If empty or wrong, hotplug may not be updating correctly
   # Check hotplug script has dynamic gateway detection
   ```

2. **Policy rules not persistent:**
   ```bash
   # Rules in rc.local only run at boot
   # VPN restart doesn't re-run rc.local

   # Check rc.local uses "add" not "replace"
   # "add" fails silently if rule exists (safe)
   # This is correct behavior - rules persist across VPN restarts
   ```

3. **Watchdog using old gateway:**
   ```bash
   # Check watchdog configuration
   grep -i gateway /etc/awg-watchdog.sh

   # If hardcoded, update to dynamic detection
   ```

### DNS Not Working for Bypass Devices

**Symptoms:**
- Bypass device can ping IPs but not domains
- DNS queries timing out

**Diagnosis:**

```bash
# From bypass device
nslookup google.com 192.168.1.5    # Test AdGuard
nslookup google.com 1.1.1.1         # Test external DNS
```

**Solutions:**

1. **AdGuard not in bypass list:**
   ```bash
   # If bypass device queries AdGuard, and AdGuard routes via VPN,
   # AdGuard's upstream queries go via VPN.
   # If VPN is slow/down, DNS fails for bypass devices.

   # FIX: Add AdGuard to bypass
   ip rule add from 192.168.1.5 lookup 100 priority 100

   # Add to /etc/rc.local for persistence
   ```

2. **AdGuard upstream unreachable:**
   ```bash
   # If AdGuard uses DoH to VPN provider (e.g., Mullvad)
   # and AdGuard is in bypass, HTTPS to Mullvad still works
   # (it's encrypted, doesn't need VPN tunnel)

   # Verify AdGuard bypass is working
   curl -s https://am.i.mullvad.net/connected
   # From AdGuard container - should show "not connected"
   ```

3. **Use external DNS for bypass devices:**
   ```bash
   # Alternative: Configure bypass devices to use external DNS directly
   # e.g., 1.1.1.1, 8.8.8.8, or VPN provider's DNS

   # This bypasses AdGuard entirely for bypass devices
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

# Check external IP (should show VPN exit IP, not ISP IP)
curl ifconfig.me
curl ipinfo.io/ip

# Provider-specific VPN check (Mullvad only)
# curl https://am.i.mullvad.net/connected

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
