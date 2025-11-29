#!/bin/bash
# =============================================================================
# Privacy Router - Container Entrypoint
# =============================================================================
# Initializes VPN tunnel, applies kill switch, starts watchdog
# =============================================================================

set -e

# =============================================================================
# Logging
# =============================================================================
LOG_FILE="/var/log/privacy-router.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_error() {
    log "ERROR: $1" >&2
}

# =============================================================================
# Validation
# =============================================================================
validate_config() {
    log "Validating configuration..."

    # Check required environment variables
    if [[ -z "$VPN_IP" ]]; then
        log_error "VPN_IP not set. Set in .env file."
        exit 1
    fi

    if [[ -z "$VPN_ENDPOINT_IP" ]]; then
        log_error "VPN_ENDPOINT_IP not set. Set in .env file."
        exit 1
    fi

    # Check config file exists
    if [[ ! -f /etc/amneziawg/awg0.conf ]]; then
        log_error "VPN config not found at /etc/amneziawg/awg0.conf"
        log_error "Copy config/awg0.conf.example to config/awg0.conf and fill in your credentials"
        exit 1
    fi

    # Check for placeholder values in config
    if grep -q "YOUR_PRIVATE_KEY_HERE\|SERVER_PUBLIC_KEY_HERE" /etc/amneziawg/awg0.conf; then
        log_error "VPN config contains placeholder values!"
        log_error "Edit config/awg0.conf with your actual VPN credentials"
        exit 1
    fi

    # Check TUN device
    if [[ ! -c /dev/net/tun ]]; then
        log_error "/dev/net/tun not available. Ensure --device=/dev/net/tun is set"
        exit 1
    fi

    log "Configuration validated successfully"
}

# =============================================================================
# Network Setup
# =============================================================================
setup_tunnel() {
    log "Setting up AmneziaWG tunnel..."

    # Remove existing interface if present
    ip link del dev awg0 2>/dev/null || true

    # Kill any existing amneziawg-go process
    pkill -f "amneziawg-go awg0" 2>/dev/null || true

    # Start userspace AmneziaWG daemon (creates TUN interface)
    # This replaces kernel-based `ip link add dev awg0 type amneziawg`
    amneziawg-go awg0 &
    AWG_PID=$!
    sleep 2

    # Verify interface was created
    if ! ip link show awg0 >/dev/null 2>&1; then
        log_error "Failed to create awg0 interface via amneziawg-go"
        exit 1
    fi
    log "Created awg0 interface (userspace daemon PID: $AWG_PID)"

    # Apply configuration
    amneziawg setconf awg0 /etc/amneziawg/awg0.conf
    log "Applied VPN configuration"

    # Add VPN internal IP address
    ip address add "$VPN_IP" dev awg0
    log "Added VPN IP: $VPN_IP"

    # Bring interface up
    ip link set up dev awg0
    log "Interface awg0 is UP"

    # Setup routing
    setup_routing
}

setup_routing() {
    log "Configuring routing..."

    # Get default gateway (WAN gateway) for endpoint route
    local wan_gateway
    wan_gateway=$(ip route | grep "default" | grep -v awg | awk '{print $3}' | head -1)

    if [[ -z "$wan_gateway" ]]; then
        log "Warning: Could not detect WAN gateway, using LAN_GATEWAY"
        wan_gateway="$LAN_GATEWAY"
    fi

    log "WAN gateway: $wan_gateway"

    # Add specific route to VPN endpoint via WAN
    # This ensures VPN packets can reach the server
    ip route add "$VPN_ENDPOINT_IP" via "$wan_gateway" 2>/dev/null || true
    log "Added endpoint route: $VPN_ENDPOINT_IP via $wan_gateway"

    # Remove default route (will be replaced by VPN)
    ip route del default 2>/dev/null || true

    # Add default route through VPN tunnel
    ip route add default dev awg0
    log "Default route set through awg0"
}

# =============================================================================
# Kill Switch
# =============================================================================
apply_kill_switch() {
    log "Applying kill switch..."

    if [[ -x /etc/amneziawg/postup.sh ]]; then
        /etc/amneziawg/postup.sh
    else
        log_error "postup.sh not found or not executable"
        exit 1
    fi
}

# =============================================================================
# Watchdog
# =============================================================================
start_watchdog() {
    if [[ "${WATCHDOG_ENABLED:-true}" == "true" ]]; then
        log "Starting watchdog daemon..."
        /opt/scripts/watchdog.sh &
        WATCHDOG_PID=$!
        log "Watchdog started (PID: $WATCHDOG_PID)"
    else
        log "Watchdog disabled"
    fi
}

# =============================================================================
# Signal Handlers
# =============================================================================
cleanup() {
    log "Received shutdown signal..."

    # Run predown script
    if [[ -x /etc/amneziawg/predown.sh ]]; then
        /etc/amneziawg/predown.sh
    fi

    # Kill watchdog
    [[ -n "$WATCHDOG_PID" ]] && kill "$WATCHDOG_PID" 2>/dev/null || true

    # Remove interface
    ip link del dev awg0 2>/dev/null || true

    log "Cleanup complete"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# =============================================================================
# Main
# =============================================================================
main() {
    log "=========================================="
    log "Privacy Router Starting"
    log "=========================================="
    log "VPN IP: ${VPN_IP:-not set}"
    log "VPN Endpoint: ${VPN_ENDPOINT_IP:-not set}:${VPN_ENDPOINT_PORT:-51820}"
    log "LAN Subnet: ${LAN_SUBNET:-192.168.1.0/24}"
    log "=========================================="

    # Validate
    validate_config

    # Setup tunnel
    setup_tunnel

    # Apply kill switch
    apply_kill_switch

    # Verify handshake
    log "Waiting for VPN handshake..."
    sleep 5

    if amneziawg show awg0 | grep -q "latest handshake"; then
        log "VPN handshake successful!"
    else
        log "Warning: No handshake yet. VPN may still be connecting..."
    fi

    # Start watchdog
    start_watchdog

    # Show status
    log "=========================================="
    log "Privacy Router Ready"
    log "=========================================="
    amneziawg show awg0 | tee -a "$LOG_FILE"

    # Keep container running
    log "Container running. Monitoring VPN tunnel..."

    # Wait indefinitely (or until signal)
    while true; do
        sleep 60
        # Periodic status log
        if amneziawg show awg0 | grep -q "latest handshake"; then
            log "VPN tunnel active"
        else
            log "Warning: VPN tunnel may be disconnected"
        fi
    done
}

main "$@"
