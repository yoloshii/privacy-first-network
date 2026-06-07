#!/bin/bash
# =============================================================================
# AdGuard Home DNS Health Watchdog
# =============================================================================
#
# Runs on the AdGuard HOST (not inside the container). Probes AdGuard's DNS
# responsiveness every CHECK_INTERVAL seconds. If the probe fails for
# FAIL_THRESHOLD consecutive cycles, the watchdog restarts the AdGuard
# deployment (Docker container, LXC container, or systemd service).
#
# Why this exists:
#   The AmneziaWG watchdog (awg-watchdog.sh) only monitors VPN tunnel health.
#   If AdGuard Home hangs (silent service freeze, goroutine exhaustion,
#   upstream timeout cascade), the VPN appears healthy but every device on
#   the network loses DNS — clients see "no internet" with no useful logs.
#
#   Real incident pattern:
#     - AdGuard's local PTR lookups time out against the router's dnsmasq
#     - dnsproxy goroutines pile up waiting on 2-second i/o timeouts
#     - AdGuard goes silent (no log entries) for hours
#     - All DNS queries hang because AdGuard is the only resolver
#     - User notices "internet broken" hours later, reboots, problem clears
#
# This watchdog catches that scenario in ~3 minutes (3 × 60s checks).
#
# Upstream-reachability gate (don't fight an outage you can't win):
#   A DNS failure does not always mean AdGuard is at fault. During an
#   upstream/ISP outage — especially on a CGNAT WAN (RFC 6598, 100.64.0.0/10),
#   where the carrier session can stall on reconnect — AdGuard's encrypted-DNS
#   upstream becomes unreachable and every probe fails, but restarting AdGuard
#   cannot fix an upstream that is down; it only drops DNS and wipes the cache
#   on each cycle (one such outage drove ~65 futile restarts in the field).
#   So before restarting, the watchdog ICMP-probes the public internet
#   (UPSTREAM_PROBES) over this host's default route; if NOTHING answers it
#   logs an upstream outage and skips the restart. It still restarts when the
#   internet is up but DNS specifically is dead (the real hang above). This is
#   the AdGuard-host parallel of the VPN watchdog's raw-WAN gate (Pitfall #21).
#
# Requires: dig (apt install dnsutils / dnf install bind-utils) and ping (iputils)
#
# Installation:
#   1. Copy this script to /usr/local/bin/adguard-watchdog.sh
#   2. chmod +x /usr/local/bin/adguard-watchdog.sh
#   3. Edit CONFIG section below for your deployment
#   4. Copy adguard-watchdog.service to /etc/systemd/system/
#   5. systemctl daemon-reload && systemctl enable --now adguard-watchdog
#
# =============================================================================

set -u

# =============================================================================
# CONFIG - Edit for your deployment
# =============================================================================

# AdGuard Home IP (where you reach the DNS service from this host)
ADGUARD_IP="192.168.1.5"

# Deployment type: docker | lxc | systemd
# - docker:  uses `docker restart <ADGUARD_TARGET>`
# - lxc:     uses `pct restart <ADGUARD_TARGET>`  (Proxmox)
# - systemd: uses `systemctl restart <ADGUARD_TARGET>`
DEPLOYMENT_TYPE="lxc"

# Target identifier for restart command:
# - docker:  container name (e.g., "adguardhome")
# - lxc:     CTID (e.g., "101")
# - systemd: service name (e.g., "AdGuardHome.service")
ADGUARD_TARGET="101"

# Seconds between health checks
CHECK_INTERVAL=60

# Consecutive failures before restart
FAIL_THRESHOLD=3

# Per-probe timeout in seconds
PROBE_TIMEOUT=5

# Seconds to wait after restart before checking again
RESTART_SETTLE_TIME=30

# Probe targets - need MIN_PROBES_PASS to succeed (geo-distributed, durable)
PROBE_TARGETS="cloudflare.com google.com quad9.net"
MIN_PROBES_PASS=2

# Upstream-reachability gate (ICMP, no DNS) — public anycast IPs probed before any restart, to
# distinguish a genuine AdGuard hang from an upstream/ISP/CGNAT (or VPN) outage. They egress via
# this host's default route: on a VPN-bypass host that's the raw WAN; on a VPN-routed host it's the
# tunnel. Either way, if NONE answer the public internet is down, so restarting AdGuard is futile
# (it can't reach its upstream) and only wipes the cache — skip it. See check_upstream().
UPSTREAM_PROBES="1.1.1.1 8.8.8.8 9.9.9.9"
# Skip the restart only when ALL probes fail (WAN totally dead). Keep this at 1: a real AdGuard
# hang plus one flaky probe target must NOT suppress the restart that fixes the network.
UPSTREAM_MIN_PASS=1
UPSTREAM_PROBE_TIMEOUT=3

# Log file (must be on persistent storage)
LOG="/var/log/adguard-watchdog.log"

# =============================================================================
# FUNCTIONS
# =============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
    logger -t adguard-watchdog "$1"
}

# Check if AdGuard target is running (deployment-aware)
check_target_running() {
    case "$DEPLOYMENT_TYPE" in
        docker)
            docker inspect -f '{{.State.Running}}' "$ADGUARD_TARGET" 2>/dev/null | grep -q "true"
            ;;
        lxc)
            pct status "$ADGUARD_TARGET" 2>/dev/null | grep -q "status: running"
            ;;
        systemd)
            systemctl is-active --quiet "$ADGUARD_TARGET"
            ;;
        *)
            log "ERROR: Unknown DEPLOYMENT_TYPE=$DEPLOYMENT_TYPE"
            return 1
            ;;
    esac
}

# Start target if stopped
start_target() {
    case "$DEPLOYMENT_TYPE" in
        docker)  docker start "$ADGUARD_TARGET" 2>&1 ;;
        lxc)     pct start "$ADGUARD_TARGET" 2>&1 ;;
        systemd) systemctl start "$ADGUARD_TARGET" 2>&1 ;;
    esac
}

# Hard restart of target
restart_target() {
    case "$DEPLOYMENT_TYPE" in
        docker)  docker restart "$ADGUARD_TARGET" 2>&1 ;;
        lxc)     pct stop "$ADGUARD_TARGET" 2>&1; sleep 3; pct start "$ADGUARD_TARGET" 2>&1 ;;
        systemd) systemctl restart "$ADGUARD_TARGET" 2>&1 ;;
    esac
}

# Probe AdGuard via dig — succeeds if MIN_PROBES_PASS targets resolve to IPv4
check_dns() {
    local success=0
    local target
    for target in $PROBE_TARGETS; do
        if dig "@${ADGUARD_IP}" +tries=1 +time="$PROBE_TIMEOUT" +short "$target" 2>/dev/null | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            success=$((success + 1))
        fi
    done
    [ "$success" -ge "$MIN_PROBES_PASS" ]
}

# Is the public internet reachable at all (independent of the DNS layer we're diagnosing)?
# ICMP-only to UPSTREAM_PROBES via this host's default route. Returns true if >= UPSTREAM_MIN_PASS
# answer; with MIN_PASS=1 it returns false only when the WAN is *totally* unreachable. Lets the main
# loop skip a futile restart during an upstream/ISP/CGNAT outage (restarting AdGuard can't fix an
# upstream that's down, and each restart drops DNS + wipes the cache for ~30-60s).
check_upstream() {
    local success=0 probe
    for probe in $UPSTREAM_PROBES; do
        ping -n -c 2 -W "$UPSTREAM_PROBE_TIMEOUT" "$probe" >/dev/null 2>&1 && success=$((success + 1))
    done
    [ "$success" -ge "$UPSTREAM_MIN_PASS" ]
}

do_restart() {
    log "Restarting AdGuard ($DEPLOYMENT_TYPE: $ADGUARD_TARGET)..."
    restart_target 2>&1 | head -5 | while read line; do log "restart: $line"; done
    sleep "$RESTART_SETTLE_TIME"

    if ! check_target_running; then
        log "ERROR: Target failed to start"
        return 1
    fi
    if check_dns; then
        log "Restart successful — DNS healthy"
        return 0
    fi
    log "Restart completed but DNS still failing"
    return 1
}

# =============================================================================
# MAIN LOOP
# =============================================================================

# Validate dig is available
if ! command -v dig >/dev/null 2>&1; then
    echo "ERROR: 'dig' not found. Install with: apt install dnsutils  (or dnf install bind-utils)" >&2
    exit 1
fi

log "AdGuard watchdog started — type=$DEPLOYMENT_TYPE target=$ADGUARD_TARGET probes=[$PROBE_TARGETS] threshold=${FAIL_THRESHOLD}x${CHECK_INTERVAL}s upstream-gate=[$UPSTREAM_PROBES] min=$UPSTREAM_MIN_PASS"

fail_count=0
consecutive_restart_fails=0

while true; do
    sleep "$CHECK_INTERVAL"

    if ! check_target_running; then
        log "Target not running — attempting start"
        start_target | head -3 | while read line; do log "start: $line"; done
        sleep "$RESTART_SETTLE_TIME"
        continue
    fi

    if check_dns; then
        if [ "$fail_count" -gt 0 ]; then
            log "DNS recovered after $fail_count failed checks"
        fi
        fail_count=0
        consecutive_restart_fails=0
        continue
    fi

    fail_count=$((fail_count + 1))
    log "DNS check failed (${fail_count}/${FAIL_THRESHOLD})"

    if [ "$fail_count" -lt "$FAIL_THRESHOLD" ]; then
        continue
    fi

    # Threshold reached. Upstream-reachability gate (don't restart into an outage you can't fix):
    # a DNS failure while the public internet is unreachable is an upstream/ISP/CGNAT (or VPN)
    # outage, NOT an AdGuard hang — restarting can't fix it and only wipes the cache. Only restart
    # when the internet is up but DNS is still failing (the genuine hang).
    fail_count=0
    if ! check_upstream; then
        log "DNS failing but upstream internet unreachable (${UPSTREAM_PROBES}) — ISP/CGNAT or VPN outage, not AdGuard. Skipping restart."
        consecutive_restart_fails=0
        sleep 300
        continue
    fi

    if do_restart; then
        consecutive_restart_fails=0
    else
        consecutive_restart_fails=$((consecutive_restart_fails + 1))
        log "Consecutive restart failures: $consecutive_restart_fails"
        if [ "$consecutive_restart_fails" -ge 3 ]; then
            log "3 consecutive restart failures — backing off 5 minutes"
            sleep 300
            consecutive_restart_fails=0
        fi
    fi
done
