#!/bin/bash
# =============================================================================
# Docker Health Check
# =============================================================================
# 5-layer health check for VPN tunnel
# Returns 0 (healthy) or 1 (unhealthy)
#
# Docker will restart container after consecutive failures
# =============================================================================

set -e

MAX_HANDSHAKE_AGE=180  # 3 minutes in seconds

# -----------------------------------------------------------------------------
# CHECK 1: Interface exists
# -----------------------------------------------------------------------------
if ! ip link show awg0 &>/dev/null; then
    echo "UNHEALTHY: awg0 interface missing"
    exit 1
fi

# -----------------------------------------------------------------------------
# CHECK 2: Interface is UP
# -----------------------------------------------------------------------------
if ! ip link show awg0 | grep -q "state UP\|state UNKNOWN"; then
    echo "UNHEALTHY: awg0 interface DOWN"
    exit 1
fi

# -----------------------------------------------------------------------------
# CHECK 3: Recent handshake
# -----------------------------------------------------------------------------
HANDSHAKE_LINE=$(amneziawg show awg0 2>/dev/null | grep "latest handshake" || echo "")

if [[ -z "$HANDSHAKE_LINE" ]]; then
    echo "UNHEALTHY: No VPN handshake detected"
    exit 1
fi

# Parse handshake age
# Format: "  latest handshake: X seconds/minutes/hours ago"
HANDSHAKE_VALUE=$(echo "$HANDSHAKE_LINE" | awk '{print $3}')
HANDSHAKE_UNIT=$(echo "$HANDSHAKE_LINE" | awk '{print $4}')

case "$HANDSHAKE_UNIT" in
    second*)
        HANDSHAKE_SECS=$HANDSHAKE_VALUE
        ;;
    minute*)
        HANDSHAKE_SECS=$((HANDSHAKE_VALUE * 60))
        ;;
    hour*)
        HANDSHAKE_SECS=$((HANDSHAKE_VALUE * 3600))
        ;;
    *)
        HANDSHAKE_SECS=9999
        ;;
esac

if [[ $HANDSHAKE_SECS -gt $MAX_HANDSHAKE_AGE ]]; then
    echo "UNHEALTHY: Handshake too old (${HANDSHAKE_SECS}s > ${MAX_HANDSHAKE_AGE}s)"
    exit 1
fi

# -----------------------------------------------------------------------------
# CHECK 4: Connectivity through tunnel
# -----------------------------------------------------------------------------
# Try multiple targets in case one is temporarily unreachable
PROBE_TARGETS="${PROBE_TARGETS:-1.1.1.1 8.8.8.8 9.9.9.9}"
PING_SUCCESS=false

for target in $PROBE_TARGETS; do
    if ping -c 1 -W 5 -I awg0 "$target" &>/dev/null; then
        PING_SUCCESS=true
        break
    fi
done

if [[ "$PING_SUCCESS" != "true" ]]; then
    echo "UNHEALTHY: Cannot ping through VPN tunnel"
    exit 1
fi

# -----------------------------------------------------------------------------
# CHECK 5: Exit IP verification (optional)
# -----------------------------------------------------------------------------
# Only run if EXPECTED_EXIT_IP is set
if [[ -n "$EXPECTED_EXIT_IP" ]]; then
    CURRENT_IP=$(curl -s --max-time 10 --interface awg0 https://ipinfo.io/ip 2>/dev/null || echo "")

    if [[ -z "$CURRENT_IP" ]]; then
        echo "UNHEALTHY: Could not retrieve exit IP"
        exit 1
    fi

    if [[ "$CURRENT_IP" != "$EXPECTED_EXIT_IP" ]]; then
        echo "UNHEALTHY: Exit IP mismatch (got: $CURRENT_IP, expected: $EXPECTED_EXIT_IP)"
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# All checks passed
# -----------------------------------------------------------------------------
echo "HEALTHY: VPN tunnel operational (handshake: ${HANDSHAKE_SECS}s ago)"
exit 0
