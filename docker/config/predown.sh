#!/bin/bash
# =============================================================================
# Kill Switch - PreDown Script
# =============================================================================
# Runs when VPN tunnel goes down
#
# IMPORTANT: Kill switch rules STAY ACTIVE
# DROP policies remain in place - no traffic leaks
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PREDOWN: $1"
}

log "VPN tunnel going down..."

# Clear connection tracking to prevent stale connections
# This ensures old connections don't bypass the kill switch
conntrack -F 2>/dev/null || true

log "Connection tracking flushed"

# Log kill switch engagement
log "KILL SWITCH ENGAGED - All internet traffic blocked"
log "VPN must reconnect before traffic will flow"

# Note: We do NOT remove iptables rules here
# The DROP policies remain active, blocking all traffic
# This is intentional - it's the kill switch protecting you

# The watchdog or Docker restart will bring the tunnel back up
# When it does, postup.sh will re-apply the rules

exit 0
