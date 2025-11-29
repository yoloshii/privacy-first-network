#!/bin/bash
# =============================================================================
# Privacy Router - Quick Test
# =============================================================================
# Fast validation for daily use (~10 seconds)
# For full validation, use test-suite.sh
#
# Usage: docker exec privacy-router /opt/scripts/quick-test.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "[${GREEN}OK${NC}] $1"; }
fail() { echo -e "[${RED}FAIL${NC}] $1"; exit 1; }

echo "Privacy Router - Quick Test"
echo "============================"

# 1. VPN Interface UP
ip link show awg0 2>/dev/null | grep -q "state UP\|state UNKNOWN" || fail "VPN interface down"
pass "VPN interface UP"

# 2. Recent Handshake
amneziawg show awg0 2>/dev/null | grep -q "latest handshake" || fail "No VPN handshake"
pass "VPN handshake active"

# 3. Tunnel HTTP (more reliable than ping through VPN)
curl -s --max-time 5 --interface awg0 http://1.1.1.1 &>/dev/null || fail "Cannot reach internet through tunnel"
pass "Tunnel connectivity"

# 4. Exit IP
EXIT_IP=$(curl -s --max-time 8 --interface awg0 https://ipinfo.io/ip 2>/dev/null || echo "")
[[ -n "$EXIT_IP" ]] || fail "Could not get exit IP"
pass "Exit IP: $EXIT_IP"

# 5. Kill Switch Rules Present
iptables -L OUTPUT -n 2>/dev/null | grep -q "DROP" || fail "Kill switch not active"
pass "Kill switch active"

echo ""
echo -e "${GREEN}All checks passed${NC}"
