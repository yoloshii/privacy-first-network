#!/bin/sh
# =============================================================================
# Watchdog Log Rotation Script
# =============================================================================
#
# Rotates watchdog log when it exceeds MAX_SIZE.
# Keeps compressed historical logs with rotation.
#
# Installation:
#   1. Copy to /etc/backup/rotate-watchdog-log.sh
#   2. chmod +x /etc/backup/rotate-watchdog-log.sh
#   3. Add to crontab: 0 4 * * * /etc/backup/rotate-watchdog-log.sh
#
# =============================================================================

LOG="/var/log/awg-watchdog.log"
MAX_SIZE=1048576  # 1MB in bytes
MAX_ROTATIONS=4

if [ ! -f "$LOG" ]; then
    exit 0
fi

# Get current log size
SIZE=$(stat -c%s "$LOG" 2>/dev/null || wc -c < "$LOG")

if [ "$SIZE" -gt "$MAX_SIZE" ]; then
    # Remove oldest rotation
    rm -f "$LOG.$MAX_ROTATIONS.gz" 2>/dev/null

    # Shift existing rotations
    i=$((MAX_ROTATIONS - 1))
    while [ $i -ge 1 ]; do
        [ -f "$LOG.$i.gz" ] && mv "$LOG.$i.gz" "$LOG.$((i + 1)).gz"
        i=$((i - 1))
    done

    # Rotate current log
    mv "$LOG" "$LOG.1"
    gzip -f "$LOG.1" 2>/dev/null

    # Create fresh log
    touch "$LOG"

    logger -t log-rotate "Rotated watchdog log (was ${SIZE} bytes)"
fi
