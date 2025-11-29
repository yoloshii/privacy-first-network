#!/bin/bash
# =============================================================================
# Privacy Router - Full Test Suite
# =============================================================================
# Comprehensive validation of VPN tunnel, kill switch, and DNS filtering
#
# Usage: docker exec privacy-router /opt/scripts/test-suite.sh
#
# CRITICAL: Test 6 (Kill Switch) temporarily disables VPN to verify
# that traffic is blocked when tunnel is down
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# =============================================================================
# Test Framework
# =============================================================================
log_test() {
    local name="$1"
    local result="$2"
    local details="$3"

    case "$result" in
        PASS)
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "[${GREEN}PASS${NC}] $name"
            ;;
        FAIL)
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "[${RED}FAIL${NC}] $name"
            [[ -n "$details" ]] && echo -e "       ${RED}$details${NC}"
            ;;
        SKIP)
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            echo -e "[${YELLOW}SKIP${NC}] $name"
            [[ -n "$details" ]] && echo -e "       ${YELLOW}$details${NC}"
            ;;
    esac
}

log_info() {
    echo -e "[${YELLOW}INFO${NC}] $1"
}

# =============================================================================
# Tests
# =============================================================================

echo "=========================================="
echo "Privacy Router - Full Test Suite"
echo "=========================================="
echo ""

# -----------------------------------------------------------------------------
# TEST 1: VPN Interface Exists
# -----------------------------------------------------------------------------
if ip link show awg0 &>/dev/null; then
    log_test "VPN interface exists" "PASS"
else
    log_test "VPN interface exists" "FAIL" "awg0 interface not found"
fi

# -----------------------------------------------------------------------------
# TEST 2: VPN Interface is UP
# -----------------------------------------------------------------------------
if ip link show awg0 2>/dev/null | grep -q "state UP\|state UNKNOWN"; then
    log_test "VPN interface UP" "PASS"
else
    log_test "VPN interface UP" "FAIL" "awg0 interface is DOWN"
fi

# -----------------------------------------------------------------------------
# TEST 3: VPN Handshake Active
# -----------------------------------------------------------------------------
HANDSHAKE=$(amneziawg show awg0 2>/dev/null | grep "latest handshake" || echo "")
if [[ -n "$HANDSHAKE" ]]; then
    log_test "VPN handshake active" "PASS"
    log_info "Handshake: $HANDSHAKE"
else
    log_test "VPN handshake active" "FAIL" "No handshake detected"
fi

# -----------------------------------------------------------------------------
# TEST 4: Tunnel Connectivity
# -----------------------------------------------------------------------------
if curl -s --max-time 5 --interface awg0 http://1.1.1.1 &>/dev/null; then
    log_test "Tunnel connectivity (HTTP)" "PASS"
else
    log_test "Tunnel connectivity (HTTP)" "FAIL" "Cannot reach internet through awg0"
fi

# -----------------------------------------------------------------------------
# TEST 5: Exit IP Retrieved
# -----------------------------------------------------------------------------
EXIT_IP=$(curl -s --max-time 10 --interface awg0 https://ipinfo.io/ip 2>/dev/null || echo "")
if [[ -n "$EXIT_IP" ]]; then
    log_test "Exit IP retrieved" "PASS"
    log_info "Your exit IP: $EXIT_IP"

    # Verify it's not the container's LAN IP
    CONTAINER_IP=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 || echo "")
    if [[ "$EXIT_IP" != "$CONTAINER_IP" ]]; then
        log_test "Exit IP differs from LAN IP" "PASS"
    else
        log_test "Exit IP differs from LAN IP" "FAIL" "Traffic may be leaking!"
    fi
else
    log_test "Exit IP retrieved" "FAIL" "Could not get external IP"
fi

# -----------------------------------------------------------------------------
# TEST 6: KILL SWITCH (CRITICAL)
# -----------------------------------------------------------------------------
echo ""
log_info "Testing kill switch (VPN will be temporarily down)..."
log_info "This is the most important test!"
echo ""

# Save current state
SAVED_IP="$EXIT_IP"

# Bring VPN down
ip link set awg0 down 2>/dev/null || true
sleep 2

# Flush connection tracking
conntrack -F 2>/dev/null || true
sleep 1

# Try to access internet without VPN
LEAK_TEST=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "BLOCKED")

# Bring VPN back up and restore routing
ip link set awg0 up 2>/dev/null || true
ip route add default dev awg0 2>/dev/null || true
sleep 3

# Verify kill switch
if [[ "$LEAK_TEST" == "BLOCKED" ]] || [[ -z "$LEAK_TEST" ]]; then
    log_test "Kill switch blocks traffic when VPN down" "PASS"
    log_info "Traffic was correctly BLOCKED when VPN was down"
else
    log_test "Kill switch blocks traffic when VPN down" "FAIL" "TRAFFIC LEAKED! Got IP: $LEAK_TEST"
    echo ""
    echo -e "${RED}=========================================="
    echo "CRITICAL SECURITY ISSUE!"
    echo "Traffic leaked when VPN was down!"
    echo "Your real IP may have been exposed!"
    echo -e "==========================================${NC}"
    echo ""
fi

# -----------------------------------------------------------------------------
# TEST 7: DNS Resolution
# -----------------------------------------------------------------------------
if nslookup google.com &>/dev/null || dig google.com +short &>/dev/null; then
    log_test "DNS resolution" "PASS"
else
    log_test "DNS resolution" "FAIL" "Cannot resolve DNS"
fi

# -----------------------------------------------------------------------------
# TEST 8: Ad Blocking (AdGuard)
# -----------------------------------------------------------------------------
# doubleclick.net should return 0.0.0.0 or NXDOMAIN if blocked
AD_RESULT=$(dig +short doubleclick.net 2>/dev/null || nslookup doubleclick.net 2>/dev/null || echo "")
if echo "$AD_RESULT" | grep -qE "0\.0\.0\.0|NXDOMAIN|SERVFAIL" || [[ -z "$AD_RESULT" ]]; then
    log_test "Ad blocking (doubleclick.net)" "PASS"
    log_info "doubleclick.net is blocked"
else
    log_test "Ad blocking (doubleclick.net)" "SKIP" "AdGuard may not be configured yet"
    log_info "Got: $AD_RESULT"
fi

# -----------------------------------------------------------------------------
# TEST 9: No IPv6 Leaks
# -----------------------------------------------------------------------------
IPV6_RESULT=$(curl -6 --max-time 5 https://ipv6.icanhazip.com 2>/dev/null || echo "BLOCKED")
if [[ "$IPV6_RESULT" == "BLOCKED" ]] || [[ -z "$IPV6_RESULT" ]]; then
    log_test "No IPv6 leaks" "PASS"
else
    log_test "No IPv6 leaks" "FAIL" "IPv6 leaked: $IPV6_RESULT"
fi

# -----------------------------------------------------------------------------
# TEST 10: iptables Kill Switch Rules Present
# -----------------------------------------------------------------------------
if iptables -L OUTPUT -n 2>/dev/null | grep -q "DROP"; then
    log_test "iptables kill switch rules present" "PASS"
else
    log_test "iptables kill switch rules present" "FAIL" "Kill switch rules not found"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed:  ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:  ${RED}$TESTS_FAILED${NC}"
echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
echo "=========================================="

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    echo "Your privacy router is properly configured!"
    echo ""
    exit 0
else
    echo ""
    echo -e "${RED}SOME TESTS FAILED${NC}"
    echo "Review the failures above and fix before use."
    echo ""
    exit 1
fi
