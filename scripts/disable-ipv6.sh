#!/bin/sh
# =============================================================================
# Disable IPv6 Script - Leak Prevention
# =============================================================================
#
# Completely disables IPv6 to prevent potential VPN leaks.
# Run once during initial setup.
#
# Usage:
#   chmod +x disable-ipv6.sh
#   ./disable-ipv6.sh
#
# =============================================================================

set -e

echo "Disabling IPv6 to prevent VPN leaks..."

# =============================================================================
# UCI Network Configuration
# =============================================================================

echo "Disabling IPv6 in network config..."

# Disable on WAN
uci set network.wan.ipv6='0'

# Disable on LAN
uci set network.lan.ipv6=''
uci delete network.lan.ip6assign 2>/dev/null || true

# Remove wan6 interface if exists
uci delete network.wan6 2>/dev/null || true

uci commit network

# =============================================================================
# UCI DHCP Configuration
# =============================================================================

echo "Disabling DHCPv6 and RA..."

# Disable DHCPv6 on LAN
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ra='disabled'

# Disable odhcpd if present
uci set dhcp.odhcpd.maindhcp='0' 2>/dev/null || true

uci commit dhcp

# =============================================================================
# Kernel Parameters
# =============================================================================

echo "Disabling IPv6 in kernel..."

# Add sysctl settings
cat >> /etc/sysctl.conf << 'EOF'

# Disable IPv6 (VPN leak prevention)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

# Apply immediately
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# =============================================================================
# Firewall Rules
# =============================================================================

echo "Adding IPv6 drop rules to firewall..."

# Drop all IPv6 traffic as extra protection
if ! uci show firewall | grep -q "option name 'Drop-IPv6'"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='Drop-IPv6-Forward'
    uci set firewall.@rule[-1].family='ipv6'
    uci set firewall.@rule[-1].proto='all'
    uci set firewall.@rule[-1].target='DROP'
    uci commit firewall
fi

# =============================================================================
# Restart Services
# =============================================================================

echo "Restarting network services..."
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
/etc/init.d/odhcpd stop 2>/dev/null || true
/etc/init.d/odhcpd disable 2>/dev/null || true

echo ""
echo "IPv6 disabled successfully!"
echo ""
echo "Verification:"
ip -6 addr 2>/dev/null || echo "No IPv6 addresses (good)"
echo ""
echo "To verify no IPv6 leaks, visit: https://ipv6leak.com"
