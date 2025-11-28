#!/bin/sh
# =============================================================================
# AmneziaWG Watchdog with Server Failover
# =============================================================================
#
# Advanced watchdog that:
# - Monitors VPN tunnel health
# - Fails over to backup servers when primary is down
# - Automatically returns to primary when it recovers
# - Maintains kill switch during failover
#
# Installation:
#   1. Copy to /etc/awg-watchdog.sh
#   2. chmod +x /etc/awg-watchdog.sh
#   3. Create server config: /etc/amneziawg/servers.conf
#   4. Create procd service (see awg-watchdog.init below)
#
# =============================================================================

# =============================================================================
# CONFIGURATION - Edit these values for your setup
# =============================================================================

# Server configuration file (contains server list)
SERVERS_FILE="/etc/amneziawg/servers.conf"

# AmneziaWG config template
CONFIG_DIR="/etc/amneziawg"

# Log file location
LOG_FILE="/var/log/awg-watchdog.log"

# Current server tracking
STATE_FILE="/tmp/awg_current_server"

# Seconds between connectivity checks
CHECK_INTERVAL=30

# Number of consecutive failures before failover
FAIL_THRESHOLD=3

# Number of successful checks before attempting failback to primary
FAILBACK_THRESHOLD=10

# IPs to ping for connectivity test (use reliable, geo-distributed targets)
PROBE_TARGETS="1.1.1.1 8.8.8.8 9.9.9.9"

# Minimum successful probes (out of total PROBE_TARGETS)
MIN_PROBES=2

# Your VPN internal IP (assigned by VPN provider)
# Example: 10.64.0.x for Mullvad, 10.x.x.x for IVPN
VPN_IP="CHANGE_ME"

# =============================================================================
# FUNCTIONS
# =============================================================================

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" >> "$LOG_FILE"
    logger -t awg-watchdog "$1"
}

# Load server list from config file
# Format: NAME ENDPOINT_IP PORT PUBLIC_KEY (one per line)
load_servers() {
    if [ ! -f "$SERVERS_FILE" ]; then
        log "ERROR: Server config not found: $SERVERS_FILE"
        exit 1
    fi

    SERVER_COUNT=$(grep -v '^#' "$SERVERS_FILE" | grep -v '^$' | wc -l)
    if [ "$SERVER_COUNT" -eq 0 ]; then
        log "ERROR: No servers defined in $SERVERS_FILE"
        exit 1
    fi

    log "Loaded $SERVER_COUNT servers from config"
}

# Get server info by index (0-based)
get_server() {
    local idx=$1
    grep -v '^#' "$SERVERS_FILE" | grep -v '^$' | sed -n "$((idx + 1))p"
}

# Get current server index
get_current_index() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo 0
    fi
}

# Save current server index
set_current_index() {
    echo "$1" > "$STATE_FILE"
}

# Detect WAN gateway (for endpoint routing)
get_wan_gateway() {
    local gw
    gw=$(ip route | grep "default via" | grep -v awg | head -1 | awk '{print $3}')
    if [ -n "$gw" ]; then
        echo "$gw"
    else
        # Fallback to common gateway
        echo "192.168.1.1"
    fi
}

# Check connectivity through VPN tunnel
check_connectivity() {
    local success=0

    for target in $PROBE_TARGETS; do
        if ping -c 1 -W 3 -I awg0 "$target" > /dev/null 2>&1; then
            success=$((success + 1))
        fi
    done

    [ "$success" -ge "$MIN_PROBES" ]
}

# Check if specific endpoint is reachable (for failback test)
check_endpoint() {
    local endpoint_ip=$1
    ping -c 1 -W 5 "$endpoint_ip" > /dev/null 2>&1
}

# Switch to a specific server
switch_server() {
    local server_line=$1
    local name endpoint port pubkey

    name=$(echo "$server_line" | awk '{print $1}')
    endpoint=$(echo "$server_line" | awk '{print $2}')
    port=$(echo "$server_line" | awk '{print $3}')
    pubkey=$(echo "$server_line" | awk '{print $4}')

    log "Switching to server: $name ($endpoint:$port)"

    local gateway
    gateway=$(get_wan_gateway)

    # 1. Tear down existing interface
    ip link del dev awg0 2>/dev/null
    sleep 1

    # 2. Create new interface
    ip link add dev awg0 type amneziawg
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to create awg0 interface"
        return 1
    fi

    # 3. Generate runtime config with new endpoint
    # Uses base config and updates endpoint
    local base_config="$CONFIG_DIR/awg0.conf"
    local runtime_config="/tmp/awg0-runtime.conf"

    # Copy base config and update endpoint
    sed "s/^Endpoint=.*/Endpoint=$endpoint:$port/" "$base_config" > "$runtime_config"

    # If public key differs, update it too (optional - depends on provider)
    if [ -n "$pubkey" ] && [ "$pubkey" != "-" ]; then
        sed -i "s/^PublicKey=.*/PublicKey=$pubkey/" "$runtime_config"
    fi

    # 4. Apply configuration
    /usr/bin/amneziawg setconf awg0 "$runtime_config"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to apply configuration for $name"
        return 1
    fi

    # 5. Assign VPN internal IP
    ip address add "$VPN_IP/32" dev awg0

    # 6. Bring interface up
    ip link set up dev awg0

    # 7. Add endpoint route via WAN gateway (prevents routing loop)
    ip route add "$endpoint" via "$gateway" 2>/dev/null

    # 8. Set default route via VPN
    ip route del default 2>/dev/null
    ip route add default dev awg0

    # Wait for handshake
    sleep 3

    # Verify connectivity
    if check_connectivity; then
        log "SUCCESS: Connected to $name"
        return 0
    else
        log "FAILED: Could not connect to $name"
        return 1
    fi
}

# Initiate failover to next server
do_failover() {
    local current_idx
    current_idx=$(get_current_index)

    log "Initiating failover from server index $current_idx"

    local tried=0
    local next_idx=$((current_idx + 1))

    while [ $tried -lt "$SERVER_COUNT" ]; do
        # Wrap around to beginning
        if [ $next_idx -ge "$SERVER_COUNT" ]; then
            next_idx=0
        fi

        local server_line
        server_line=$(get_server $next_idx)

        if switch_server "$server_line"; then
            set_current_index $next_idx
            return 0
        fi

        next_idx=$((next_idx + 1))
        tried=$((tried + 1))
    done

    log "CRITICAL: All servers failed! Kill switch remains engaged."
    return 1
}

# Check if primary is back and switch if so
try_failback() {
    local current_idx
    current_idx=$(get_current_index)

    # Only failback if not already on primary (index 0)
    if [ "$current_idx" -eq 0 ]; then
        return 0
    fi

    # Get primary server endpoint
    local primary_line primary_endpoint
    primary_line=$(get_server 0)
    primary_endpoint=$(echo "$primary_line" | awk '{print $2}')

    log "Testing if primary ($primary_endpoint) is back..."

    if check_endpoint "$primary_endpoint"; then
        log "Primary server responding - attempting failback"

        if switch_server "$primary_line"; then
            set_current_index 0
            log "Failback to primary successful"
            return 0
        else
            log "Failback failed - staying on current server"
        fi
    fi

    return 1
}

# =============================================================================
# MAIN LOOP
# =============================================================================

# Validate configuration
if [ "$VPN_IP" = "CHANGE_ME" ]; then
    echo "ERROR: Please configure VPN_IP before running"
    exit 1
fi

# Load server configuration
load_servers

# Initialize state
fail_count=0
success_count=0
set_current_index 0

log "AWG watchdog starting (check: ${CHECK_INTERVAL}s, failover: ${FAIL_THRESHOLD} failures, failback: ${FAILBACK_THRESHOLD} successes)"

# Main monitoring loop
while true; do
    if check_connectivity; then
        # Tunnel is healthy
        if [ $fail_count -gt 0 ]; then
            log "Connectivity restored"
        fi
        fail_count=0
        success_count=$((success_count + 1))

        # Check for failback opportunity
        if [ $success_count -ge $FAILBACK_THRESHOLD ]; then
            try_failback
            success_count=0
        fi
    else
        # Connectivity check failed
        fail_count=$((fail_count + 1))
        success_count=0
        log "Connectivity check failed ($fail_count/$FAIL_THRESHOLD)"

        if [ $fail_count -ge $FAIL_THRESHOLD ]; then
            # Threshold reached, failover
            do_failover
            fail_count=0
            # Wait for tunnel to stabilize
            sleep 5
        fi
    fi

    sleep $CHECK_INTERVAL
done
