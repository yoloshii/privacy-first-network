#!/bin/sh
# =============================================================================
# AmneziaWG Watchdog - Basic Connectivity Monitor with Auto-Recovery
# =============================================================================
#
# Simple watchdog that monitors VPN tunnel health and restarts on failure.
# Designed for OpenWrt but works on any Linux with AmneziaWG.
#
# For ADVANCED features (server failover, failback to primary), see:
#   scripts/awg-watchdog-failover.sh
#
# Installation:
#   1. Copy to /etc/awg-watchdog.sh
#   2. chmod +x /etc/awg-watchdog.sh
#   3. Edit configuration section below
#   4. Create init script (see openwrt/init.d/awg-watchdog)
#
# Usage:
#   /etc/awg-watchdog.sh &
#
# =============================================================================

# =============================================================================
# CONFIGURATION - Edit these values for your setup
# =============================================================================

# Path to AmneziaWG configuration file
CONFIG_FILE="/etc/amneziawg/awg0.conf"

# Log file location
LOG_FILE="/var/log/awg-watchdog.log"

# Seconds between connectivity checks
CHECK_INTERVAL=30

# Number of consecutive failures before restarting tunnel
FAIL_THRESHOLD=3

# IPs to ping for connectivity test (space-separated)
# Use reliable, geo-distributed targets
PROBE_TARGETS="1.1.1.1 8.8.8.8"

# Your VPN internal IP (assigned by VPN provider)
# Example: 10.64.0.x for Mullvad
VPN_IP="CHANGE_ME"

# VPN server endpoint IP (not hostname)
ENDPOINT_IP="CHANGE_ME"

# Gateway IP for endpoint route
# Usually your modem/WAN gateway, or LAN gateway if using bridge mode
# Set to "auto" to detect from existing default route
WAN_GATEWAY="auto"

# =============================================================================
# FUNCTIONS
# =============================================================================

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" >> "$LOG_FILE"
    logger -t awg-watchdog "$1"
}

get_wan_gateway() {
    if [ "$WAN_GATEWAY" = "auto" ]; then
        # Try to get gateway from existing route (excluding awg0)
        local gw
        gw=$(ip route | grep "default via" | grep -v awg | head -1 | awk '{print $3}')
        if [ -n "$gw" ]; then
            echo "$gw"
        else
            # Fallback to common gateway
            echo "192.168.1.1"
        fi
    else
        echo "$WAN_GATEWAY"
    fi
}

check_connectivity() {
    # Ping each target through the VPN interface
    # Returns 0 (success) if any target responds
    for target in $PROBE_TARGETS; do
        if ping -c 1 -W 3 -I awg0 "$target" > /dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

check_interface() {
    # Check if awg0 interface exists and is up
    if ip link show awg0 2>/dev/null | grep -q "state UP"; then
        return 0
    fi
    return 1
}

restart_tunnel() {
    log "Restarting AmneziaWG tunnel"

    local gateway
    gateway=$(get_wan_gateway)

    # 1. Teardown existing interface
    ip link del dev awg0 2>/dev/null
    sleep 1

    # 2. Create new interface
    ip link add dev awg0 type amneziawg
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to create awg0 interface"
        return 1
    fi

    # 3. Apply configuration
    /usr/bin/amneziawg setconf awg0 "$CONFIG_FILE"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to apply configuration"
        return 1
    fi

    # 4. Assign VPN internal IP
    ip address add "$VPN_IP/32" dev awg0

    # 5. Bring interface up
    ip link set up dev awg0

    # 6. CRITICAL: Add endpoint route BEFORE default route
    # This prevents routing loop (VPN traffic must go via WAN, not via VPN)
    ip route add "$ENDPOINT_IP" via "$gateway" 2>/dev/null

    # 7. Set default route via VPN
    ip route del default 2>/dev/null
    ip route add default dev awg0

    log "Tunnel restarted (gateway: $gateway)"
    return 0
}

# =============================================================================
# MAIN LOOP
# =============================================================================

# Validate configuration
if [ "$VPN_IP" = "CHANGE_ME" ] || [ "$ENDPOINT_IP" = "CHANGE_ME" ]; then
    echo "ERROR: Please configure VPN_IP and ENDPOINT_IP before running"
    exit 1
fi

# Initialize
fail_count=0
log "AWG watchdog starting (check interval: ${CHECK_INTERVAL}s, threshold: ${FAIL_THRESHOLD})"

# Main monitoring loop
while true; do
    if check_interface && check_connectivity; then
        # Tunnel is healthy
        if [ $fail_count -gt 0 ]; then
            log "Connectivity restored"
        fi
        fail_count=0
    else
        # Connectivity check failed
        fail_count=$((fail_count + 1))
        log "Connectivity check failed ($fail_count/$FAIL_THRESHOLD)"

        if [ $fail_count -ge $FAIL_THRESHOLD ]; then
            # Threshold reached, restart tunnel
            restart_tunnel
            fail_count=0
            # Wait a bit for tunnel to establish
            sleep 5
        fi
    fi

    sleep $CHECK_INTERVAL
done
