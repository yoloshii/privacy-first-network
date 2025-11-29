#!/bin/bash
# =============================================================================
# VPN Watchdog - Auto-Recovery Daemon
# =============================================================================
# Monitors VPN tunnel health and restarts if necessary
# Runs as background process inside the container
#
# Configuration via environment variables:
#   WATCHDOG_INTERVAL      - Seconds between checks (default: 30)
#   WATCHDOG_FAIL_THRESHOLD - Failures before restart (default: 3)
#   PROBE_TARGETS          - IPs to ping (default: 1.1.1.1 8.8.8.8 9.9.9.9)
# =============================================================================

LOG_FILE="/var/log/awg-watchdog.log"

# Configuration
CHECK_INTERVAL="${WATCHDOG_INTERVAL:-30}"
FAIL_THRESHOLD="${WATCHDOG_FAIL_THRESHOLD:-3}"
PROBE_TARGETS="${PROBE_TARGETS:-1.1.1.1 8.8.8.8 9.9.9.9}"

# State
fail_count=0

# =============================================================================
# Logging
# =============================================================================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] WATCHDOG: $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# =============================================================================
# Health Checks
# =============================================================================
check_interface() {
    ip link show awg0 2>/dev/null | grep -q "state UP\|state UNKNOWN"
}

check_handshake() {
    amneziawg show awg0 2>/dev/null | grep -q "latest handshake"
}

check_connectivity() {
    for target in $PROBE_TARGETS; do
        if ping -c 1 -W 3 -I awg0 "$target" &>/dev/null; then
            return 0
        fi
    done
    return 1
}

# =============================================================================
# Tunnel Restart
# =============================================================================
restart_tunnel() {
    log "=========================================="
    log "RESTARTING VPN TUNNEL"
    log "=========================================="

    # Run predown script
    if [[ -x /etc/amneziawg/predown.sh ]]; then
        /etc/amneziawg/predown.sh
    fi

    # Remove existing interface and kill userspace daemon
    ip link del dev awg0 2>/dev/null || true
    pkill -f "amneziawg-go awg0" 2>/dev/null || true
    sleep 2

    # Start userspace AmneziaWG daemon (creates TUN interface)
    log "Creating awg0 interface (userspace daemon)..."
    amneziawg-go awg0 &
    sleep 2

    # Verify interface was created
    if ! ip link show awg0 >/dev/null 2>&1; then
        log "ERROR: Failed to create awg0 interface"
        return 1
    fi

    # Apply configuration
    log "Applying VPN configuration..."
    amneziawg setconf awg0 /etc/amneziawg/awg0.conf

    # Add IP address
    log "Adding VPN IP: $VPN_IP"
    ip address add "$VPN_IP" dev awg0

    # Bring interface up
    ip link set up dev awg0
    log "Interface awg0 UP"

    # Setup routing
    log "Configuring routes..."

    # Get WAN gateway
    local wan_gateway
    wan_gateway=$(ip route | grep "default" | grep -v awg | awk '{print $3}' | head -1)
    [[ -z "$wan_gateway" ]] && wan_gateway="$LAN_GATEWAY"

    # Add endpoint route
    ip route add "$VPN_ENDPOINT_IP" via "$wan_gateway" 2>/dev/null || true

    # Set default route through VPN
    ip route del default 2>/dev/null || true
    ip route add default dev awg0

    # Re-apply kill switch
    log "Re-applying kill switch..."
    if [[ -x /etc/amneziawg/postup.sh ]]; then
        /etc/amneziawg/postup.sh
    fi

    log "Tunnel restart complete"
    log "=========================================="

    # Give tunnel time to establish
    sleep 5
}

# =============================================================================
# Main Loop
# =============================================================================
main() {
    log "=========================================="
    log "Watchdog starting"
    log "  Check interval: ${CHECK_INTERVAL}s"
    log "  Fail threshold: ${FAIL_THRESHOLD}"
    log "  Probe targets: $PROBE_TARGETS"
    log "=========================================="

    while true; do
        # Run health checks
        if check_interface && check_handshake && check_connectivity; then
            # Success
            if [[ $fail_count -gt 0 ]]; then
                log "Connectivity restored after $fail_count failures"
            fi
            fail_count=0
        else
            # Failure
            fail_count=$((fail_count + 1))
            log "Health check FAILED ($fail_count/$FAIL_THRESHOLD)"

            # Log which check failed
            check_interface || log "  - Interface check failed"
            check_handshake || log "  - Handshake check failed"
            check_connectivity || log "  - Connectivity check failed"

            # Restart if threshold reached
            if [[ $fail_count -ge $FAIL_THRESHOLD ]]; then
                log "Fail threshold reached - initiating restart"
                restart_tunnel
                fail_count=0
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
