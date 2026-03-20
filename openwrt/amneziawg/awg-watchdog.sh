#!/bin/sh
# =============================================================================
# AmneziaWG Watchdog with Server Failover
# =============================================================================
#
# Advanced watchdog that:
# - Monitors VPN tunnel health
# - Differentiates ISP outage from VPN failure (WAN gateway pre-check)
# - Checks WireGuard handshake freshness before restarting
# - Attempts soft bounce (re-handshake) before destructive restart
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

# Seconds to wait for each probe ping reply
# On high-latency links (VPN RTT >150ms), 3s may cause false failures.
# Formula: set this to at least (VPN_RTT_ms / 1000) + 3
PROBE_TIMEOUT=5

# Number of ping packets per probe (any reply = probe passes)
# Single-packet probes are binary pass/fail — no tolerance for jitter.
# 2 packets gives resilience against single dropped packets.
PROBE_COUNT=2

# Seconds — handshake younger than this means tunnel is cryptographically alive.
# WireGuard re-handshakes every 2 minutes under traffic, so 120s is a safe threshold.
# If handshake is fresh but probes fail, the issue is likely transient (ISP jitter).
HANDSHAKE_FRESH=120

# Your VPN internal IP (assigned by VPN provider)
# Example: 10.64.0.x for Mullvad, 10.x.x.x for IVPN
# Get this from your provider's WireGuard config generator
VPN_IP="CHANGE_ME"

# LAN bridge interface name (for bypass routing table)
LAN_IFACE="br-lan"

# Seconds to wait after tunnel restart before checking connectivity
# Must be long enough for WireGuard handshake on high-latency links.
# Too short = false "restart FAILED" even when tunnel is actually up.
RESTART_SETTLE_TIME=12

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
# Uses multi-packet probes with generous timeout for high-latency links
check_connectivity() {
    local success=0

    for target in $PROBE_TARGETS; do
        if ping -c "$PROBE_COUNT" -W "$PROBE_TIMEOUT" -I awg0 "$target" > /dev/null 2>&1; then
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

# Check if WAN gateway is reachable (differentiates ISP outage from VPN failure)
# If WAN gateway is down, restarting the VPN tunnel is pointless.
check_wan() {
    local gw
    gw=$(get_wan_gateway)
    [ -z "$gw" ] && return 1
    ping -c 2 -W 3 "$gw" > /dev/null 2>&1
}

# Check if WireGuard handshake is recent (tunnel alive even if probes fail)
# A fresh handshake means the crypto session is active — the tunnel is up,
# and probe failures are likely caused by transient upstream packet loss.
check_handshake_fresh() {
    local hs_epoch
    hs_epoch=$($AWG_CMD show awg0 latest-handshakes 2>/dev/null | awk '{print $2}')
    [ -z "$hs_epoch" ] && return 1
    [ "$hs_epoch" = "0" ] && return 1
    local now age
    now=$(date +%s)
    age=$((now - hs_epoch))
    [ "$age" -lt "$HANDSHAKE_FRESH" ]
}

# Get current rx bytes from WireGuard transfer stats (cumulative)
get_rx_bytes() {
    $AWG_CMD show awg0 transfer 2>/dev/null | awk '{print $2}'
}

# Check if tunnel is passing traffic (rx bytes changed since last snapshot).
# A tunnel with a fresh handshake but zero rx change is a "zombie" —
# the crypto session completed but data isn't flowing (broken NAT,
# stale conntrack, CGNAT reassigned the mapping, etc).
check_transfer_active() {
    local current_rx
    current_rx=$(get_rx_bytes)
    [ -z "$current_rx" ] && return 1
    [ "$current_rx" = "$LAST_RX_BYTES" ] && return 1
    return 0
}

# Force traffic through tunnel to trigger re-handshake without teardown.
# This is much less disruptive than a full restart — no route teardown,
# no conntrack flush, no brief outage for all connected devices.
soft_bounce() {
    log "Soft bounce: forcing re-handshake without teardown"
    local first_probe
    first_probe=$(echo $PROBE_TARGETS | awk '{print $1}')
    ping -c 2 -W 10 -I awg0 "$first_probe" > /dev/null 2>&1
    sleep 5
    if check_connectivity; then
        log "Soft bounce recovered connectivity"
        return 0
    fi
    log "Soft bounce did not recover connectivity"
    return 1
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
LAST_RX_BYTES=$(get_rx_bytes)
set_current_index 0

log "AWG watchdog starting (check: ${CHECK_INTERVAL}s, probe: ${PROBE_COUNT}x${PROBE_TIMEOUT}s, failover after: ${FAIL_THRESHOLD} failures, failback after: ${FAILBACK_THRESHOLD} successes)"

# Main monitoring loop
while true; do
    sleep $CHECK_INTERVAL

    if check_connectivity; then
        # Tunnel is healthy — snapshot rx bytes for zombie detection
        LAST_RX_BYTES=$(get_rx_bytes)
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
        continue
    fi

    # Connectivity check failed
    fail_count=$((fail_count + 1))
    success_count=0
    log "Connectivity check failed ($fail_count/$FAIL_THRESHOLD)"

    if [ $fail_count -lt $FAIL_THRESHOLD ]; then
        continue
    fi

    # Hit threshold — begin recovery gates
    fail_count=0

    # Gate 1: Is WAN itself reachable?
    # If the ISP/WAN link is down, restarting the VPN is pointless.
    if ! check_wan; then
        log "WAN gateway unreachable — ISP issue, not VPN. Skipping restart."
        continue
    fi

    # Gate 2: Is the tunnel handshake still fresh?
    # A recent handshake means the crypto session is alive — probes failed
    # due to transient packet loss, not a dead tunnel. Try a soft bounce
    # (force re-handshake) instead of tearing everything down.
    #
    # Exception: if handshake is fresh but rx bytes haven't changed since
    # the last successful check, the tunnel is a "zombie" — crypto alive
    # but not passing traffic. Skip soft bounce and go straight to restart.
    if check_handshake_fresh; then
        if ! check_transfer_active; then
            log "Zombie tunnel: handshake fresh but zero rx change — skipping soft bounce"
        elif soft_bounce; then
            LAST_RX_BYTES=$(get_rx_bytes)
            consecutive_restart_fails=0
            continue
        else
            log "Handshake fresh but soft bounce failed — proceeding to full restart"
        fi
    else
        log "Handshake stale — proceeding to full restart"
    fi

    # Gate 3: Full restart
    # First attempt: restart on same server (handles transient issues)
    # Subsequent attempts: cycle to next server (handles server-level failures)
    if [ $consecutive_restart_fails -eq 0 ]; then
        restart_current
    else
        do_failover
    fi
    restart_result=$?

    # Use the restart function's return value directly.
    # Do NOT run check_connectivity again here — the restart functions
    # already verify connectivity internally. A second check races against
    # network stabilization and causes false "restart failed" reports.
    if [ $restart_result -ne 0 ]; then
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
done
