#!/bin/bash
# =============================================================================
# Kill Switch - PostUp Script
# =============================================================================
# Applied after VPN tunnel comes up
# Implements iptables rules that ONLY allow traffic through VPN
#
# SECURITY: Default policy is DROP - if VPN fails, all traffic blocked
# =============================================================================

set -e

# Load environment variables (passed from entrypoint)
VPN_ENDPOINT_IP="${VPN_ENDPOINT_IP:?VPN_ENDPOINT_IP not set}"
VPN_ENDPOINT_PORT="${VPN_ENDPOINT_PORT:-51820}"
LAN_SUBNET="${LAN_SUBNET:-192.168.1.0/24}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] POSTUP: $1"
}

log "Applying kill switch rules..."

# =============================================================================
# IPv4 Rules
# =============================================================================

# Flush existing rules
iptables -F INPUT
iptables -F OUTPUT
iptables -F FORWARD
iptables -t nat -F POSTROUTING

# Set default policies to DROP (kill switch foundation)
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

log "Default policies set to DROP"

# -----------------------------------------------------------------------------
# INPUT Rules (traffic TO this container)
# -----------------------------------------------------------------------------

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established/related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow from LAN (for DNS, management)
iptables -A INPUT -s "$LAN_SUBNET" -j ACCEPT

# Allow from VPN tunnel
iptables -A INPUT -i awg0 -j ACCEPT

# Allow ICMP (ping) for diagnostics
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

log "INPUT rules applied"

# -----------------------------------------------------------------------------
# OUTPUT Rules (traffic FROM this container)
# -----------------------------------------------------------------------------

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established/related connections
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow to LAN
iptables -A OUTPUT -d "$LAN_SUBNET" -j ACCEPT

# CRITICAL: Only UDP to VPN endpoint allowed to escape container
# This is the ONLY non-VPN traffic permitted
iptables -A OUTPUT -p udp -d "$VPN_ENDPOINT_IP" --dport "$VPN_ENDPOINT_PORT" -j ACCEPT

# Allow ALL traffic through VPN tunnel
iptables -A OUTPUT -o awg0 -j ACCEPT

# Allow ICMP for diagnostics
iptables -A OUTPUT -p icmp -j ACCEPT

log "OUTPUT rules applied"

# -----------------------------------------------------------------------------
# FORWARD Rules (LAN gateway - routing traffic for other devices)
# -----------------------------------------------------------------------------

# Enable IP forwarding (if not already set via Docker sysctls)
if [[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]]; then
    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || log "IP forwarding already enabled via sysctls"
fi

# Allow LAN to VPN tunnel
iptables -A FORWARD -i eth0 -o awg0 -s "$LAN_SUBNET" -j ACCEPT

# Allow established/related back to LAN
iptables -A FORWARD -i awg0 -o eth0 -d "$LAN_SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

log "FORWARD rules applied"

# -----------------------------------------------------------------------------
# NAT (Masquerade for LAN gateway)
# -----------------------------------------------------------------------------

# Masquerade all traffic going out the VPN tunnel
iptables -t nat -A POSTROUTING -o awg0 -j MASQUERADE

log "NAT masquerade applied"

# =============================================================================
# IPv6 Rules (Block everything - prevent leaks)
# =============================================================================

# Flush IPv6 rules
ip6tables -F INPUT 2>/dev/null || true
ip6tables -F OUTPUT 2>/dev/null || true
ip6tables -F FORWARD 2>/dev/null || true

# Block all IPv6
ip6tables -P INPUT DROP 2>/dev/null || true
ip6tables -P OUTPUT DROP 2>/dev/null || true
ip6tables -P FORWARD DROP 2>/dev/null || true

# Only allow loopback
ip6tables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

log "IPv6 blocked (leak prevention)"

# =============================================================================
# Logging for debugging (rate-limited)
# =============================================================================

# Log dropped OUTPUT packets (helps debug connectivity issues)
iptables -A OUTPUT -j LOG --log-prefix "KILLSWITCH-OUT-DROP: " --log-level 4 -m limit --limit 5/min

# Log dropped FORWARD packets
iptables -A FORWARD -j LOG --log-prefix "KILLSWITCH-FWD-DROP: " --log-level 4 -m limit --limit 5/min

log "Kill switch active - only VPN traffic allowed"
log "VPN endpoint: $VPN_ENDPOINT_IP:$VPN_ENDPOINT_PORT"
log "LAN subnet: $LAN_SUBNET"
