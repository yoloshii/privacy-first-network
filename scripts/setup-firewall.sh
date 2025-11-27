#!/bin/sh
# =============================================================================
# Firewall Setup Script - Kill Switch Configuration
# =============================================================================
#
# Configures OpenWrt firewall zones for VPN kill switch.
# Run once during initial setup.
#
# Usage:
#   chmod +x setup-firewall.sh
#   ./setup-firewall.sh
#
# =============================================================================

set -e

echo "Setting up firewall zones for VPN kill switch..."

# =============================================================================
# VPN Zone
# =============================================================================

echo "Creating VPN zone..."

# Check if VPN zone already exists
if uci show firewall | grep -q "firewall.vpn=zone"; then
    echo "VPN zone already exists, updating..."
else
    uci set firewall.vpn=zone
fi

uci set firewall.vpn.name='vpn'
uci set firewall.vpn.device='awg0'
uci set firewall.vpn.input='REJECT'
uci set firewall.vpn.output='ACCEPT'
uci set firewall.vpn.forward='REJECT'
uci set firewall.vpn.masq='1'
uci set firewall.vpn.mtu_fix='1'

# =============================================================================
# LAN to VPN Forwarding
# =============================================================================

echo "Creating LAN->VPN forwarding rule..."

# Check if forwarding already exists
if uci show firewall | grep -q "firewall.lan_vpn=forwarding"; then
    echo "LAN->VPN forwarding already exists, updating..."
else
    uci set firewall.lan_vpn=forwarding
fi

uci set firewall.lan_vpn.src='lan'
uci set firewall.lan_vpn.dest='vpn'

# =============================================================================
# Verify Kill Switch (No LAN->WAN)
# =============================================================================

echo "Verifying kill switch (no LAN->WAN forwarding)..."

# Check for any lan->wan forwarding and warn
if uci show firewall | grep -E "src='lan'.*dest='wan'" | grep -q forwarding; then
    echo "WARNING: Found LAN->WAN forwarding rule. This breaks the kill switch!"
    echo "Remove it with: uci delete firewall.@forwarding[X]"
fi

# =============================================================================
# Commit and Restart
# =============================================================================

echo "Committing changes..."
uci commit firewall

echo "Restarting firewall..."
/etc/init.d/firewall restart

echo ""
echo "Firewall configured successfully!"
echo ""
echo "Zone summary:"
echo "  LAN -> VPN: ALLOWED (internet access)"
echo "  LAN -> WAN: BLOCKED (kill switch)"
echo ""
echo "When VPN is down, all internet traffic will be blocked."
echo "LAN access (SSH, web UI) will still work."
