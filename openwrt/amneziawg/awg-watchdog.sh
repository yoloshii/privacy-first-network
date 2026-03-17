#!/bin/sh
# =============================================================================
# AmneziaWG Watchdog with Server Failover
# =============================================================================
#
# Advanced watchdog that:
# - Monitors VPN tunnel health
# - Fails over to backup servers when primary is down
# - Tries same server first, then cycles on repeated failures
# - Backs off after exhausting all servers
# - Automatically returns to primary when it recovers
# - Maintains kill switch and bypass routing during failover
# - Forces handshake after tunnel restart for reliable detection
#
# Installation:
#   1. Copy to /etc/awg-watchdog.sh
#   2. chmod +x /etc/awg-watchdog.sh
#   3. Create server config: /etc/amneziawg/servers.conf
#   4. Create procd service (see awg-watchdog.init)
#   5. Enable: /etc/init.d/awg-watchdog enable
#   6. Start: /etc/init.d/awg-watchdog start
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

# Number of consecutive failures before restart attempt
FAIL_THRESHOLD=3

# Number of successful checks before attempting failback to primary
FAILBACK_THRESHOLD=10

# IPs to ping for connectivity test (use reliable, geo-distributed targets)
PROBE_TARGETS="1.1.1.1 8.8.8.8 9.9.9.9"

# Minimum successful probes (out of total PROBE_TARGETS)
MIN_PROBES=2

# Your VPN internal IP (assigned by VPN provider)
# Example: 10.64.0.x for Mullvad, 10.x.x.x for IVPN
# Get this from your provider's WireGuard config generator
VPN_IP="CHANGE_ME"

# LAN bridge interface name (for bypass routing table)
LAN_IFACE="br-lan"

# Seconds to wait after tunnel restart before checking connectivity
# WireGuard keepalive is typically 25s — allow enough time for handshake
RESTART_SETTLE_TIME=5

# Seconds to back off after all servers have been tried and failed
EXHAUSTION_BACKOFF=300

# Obfuscation profile (AmneziaWG 1.5)
# Options: basic, quic, dns, sip, stealth
# All profiles work with standard WireGuard servers
AWG_PROFILE="basic"

# =============================================================================
# COMMAND DETECTION
# =============================================================================
# AmneziaWG command name varies by installation method:
#   - OpenWrt packages from awg-openwrt: "awg"
#   - Built from source or other distros: "amneziawg"

if command -v awg >/dev/null 2>&1; then
    AWG_CMD="awg"
elif command -v amneziawg >/dev/null 2>&1; then
    AWG_CMD="amneziawg"
else
    echo "ERROR: Neither 'awg' nor 'amneziawg' found in PATH"
    echo "Install AmneziaWG: https://github.com/amnezia-vpn/amneziawg-openwrt"
    exit 1
fi

# =============================================================================
# PROFILE SUPPORT
# =============================================================================
# Source shared profile library if available
PROFILES_LIB="/etc/amneziawg/awg-profiles.sh"
if [ -f "$PROFILES_LIB" ]; then
    . "$PROFILES_LIB"
    PROFILES_AVAILABLE=1
else
    PROFILES_AVAILABLE=0
fi

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
# Uses same logic as hotplug for consistency
get_wan_gateway() {
    local gw
    # Try: current routing table (non-VPN default route)
    gw=$(ip route | grep "default via" | grep -v awg | head -1 | awk '{print $3}')
    # Fallback: check WAN interface directly
    [ -z "$gw" ] && gw=$(ip route show dev eth0 2>/dev/null | grep default | awk '{print $3}' | head -1)
    # Fallback: UCI network config
    [ -z "$gw" ] && gw=$(uci -q get network.wan.gateway)
    echo "$gw"
}

# Detect LAN subnet from bridge interface
get_lan_subnet() {
    local addr
    addr=$(ip -4 addr show "$LAN_IFACE" 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
    if [ -n "$addr" ]; then
        # Convert host IP to .0/24 network (covers most home networks)
        echo "$addr" | sed 's/\.[0-9]*$/.0\/24/'
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

    if [ -z "$gateway" ]; then
        log "ERROR: Cannot determine WAN gateway"
        return 1
    fi

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
    local base_config="$CONFIG_DIR/awg0.conf"
    local runtime_config="/tmp/awg0-runtime.conf"
    local final_config="/tmp/awg0-final.conf"

    # Copy base config and update endpoint
    sed "s/^Endpoint=.*/Endpoint=$endpoint:$port/" "$base_config" > "$runtime_config"

    # If public key differs, update it too (for multi-city failover)
    # Use "-" in servers.conf to keep base config's key (same-city servers)
    if [ -n "$pubkey" ] && [ "$pubkey" != "-" ]; then
        sed -i "s/^PublicKey=.*/PublicKey=$pubkey/" "$runtime_config"
    fi

    # 3b. Apply obfuscation profile (AmneziaWG 1.5)
    if [ "$PROFILES_AVAILABLE" = "1" ]; then
        apply_awg_profile "$runtime_config" "$final_config" "$AWG_PROFILE"
        runtime_config="$final_config"
        log "Applied profile: $(get_awg_profile_description)"
    fi

    # 4. Apply configuration
    $AWG_CMD setconf awg0 "$runtime_config"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to apply configuration for $name"
        return 1
    fi

    # 5. Assign VPN internal IP
    ip address add "$VPN_IP/32" dev awg0

    # 6. Bring interface up
    ip link set up dev awg0

    # 7. Add endpoint route via WAN gateway (prevents routing loop)
    ip route replace "$endpoint" via "$gateway" dev eth0

    # 8. Maintain bypass routing table (table 100)
    ip route replace default via "$gateway" dev eth0 table 100

    # 8b. Add LAN route to bypass table
    # Without this, bypass devices cannot reach other LAN devices
    local lan_net
    lan_net=$(get_lan_subnet)
    if [ -n "$lan_net" ]; then
        ip route replace "$lan_net" dev "$LAN_IFACE" table 100
    fi

    # 9. Add VPN split routes (more specific than default, covers all IPv4)
    ip route replace 0.0.0.0/1 dev awg0
    ip route replace 128.0.0.0/1 dev awg0

    # 10. Force handshake by sending traffic through tunnel
    # WireGuard won't handshake until traffic is sent. Without this,
    # the connectivity check may fail even though the server is reachable.
    local first_probe
    first_probe=$(echo $PROBE_TARGETS | awk '{print $1}')
    ping -c 1 -W 10 -I awg0 "$first_probe" >/dev/null 2>&1
    sleep $RESTART_SETTLE_TIME

    # Verify connectivity
    if check_connectivity; then
        log "SUCCESS: Connected to $name"
        return 0
    else
        log "FAILED: Could not connect to $name"
        return 1
    fi
}

# Restart tunnel on current server (no failover)
restart_current() {
    local current_idx
    current_idx=$(get_current_index)
    local server_line
    server_line=$(get_server $current_idx)

    log "Restarting tunnel on current server (index $current_idx)"

    if switch_server "$server_line"; then
        return 0
    fi
    return 1
}

# Cycle through servers until one works
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
    echo "Get your VPN internal IP from your provider's config generator"
    exit 1
fi

# Load server configuration
load_servers

# Initialize state
fail_count=0
success_count=0
consecutive_restart_fails=0
set_current_index 0

log "AWG watchdog starting (check: ${CHECK_INTERVAL}s, failover after: ${FAIL_THRESHOLD} failures, failback after: ${FAILBACK_THRESHOLD} successes)"

# Main monitoring loop
while true; do
    sleep $CHECK_INTERVAL

    if check_connectivity; then
        # Tunnel is healthy
        if [ $fail_count -gt 0 ]; then
            log "Connectivity restored"
        fi
        fail_count=0
        consecutive_restart_fails=0
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
            # First attempt: try restarting on same server
            # (handles transient issues without unnecessary failover)
            # Subsequent attempts: cycle to next server
            if [ $consecutive_restart_fails -eq 0 ]; then
                restart_current
            else
                do_failover
            fi

            if ! check_connectivity; then
                consecutive_restart_fails=$((consecutive_restart_fails + 1))
                log "Restart failed, consecutive failures: $consecutive_restart_fails"

                # After trying all servers, back off before retrying
                if [ $consecutive_restart_fails -ge "$SERVER_COUNT" ]; then
                    log "All servers exhausted, backing off ${EXHAUSTION_BACKOFF}s before retry cycle"
                    sleep $EXHAUSTION_BACKOFF
                    consecutive_restart_fails=0
                fi
            else
                consecutive_restart_fails=0
            fi

            fail_count=0
        fi
    fi
done
