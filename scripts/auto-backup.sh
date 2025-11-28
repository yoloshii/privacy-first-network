#!/bin/sh
# =============================================================================
# OpenWrt Auto-Backup Script
# =============================================================================
#
# Creates daily compressed backups of /etc/config with rotation.
#
# Installation:
#   1. Copy to /etc/backup/auto-backup.sh
#   2. chmod +x /etc/backup/auto-backup.sh
#   3. mkdir -p /etc/backup
#   4. Add to crontab: 0 3 * * * /etc/backup/auto-backup.sh
#
# =============================================================================

BACKUP_DIR=/etc/backup
MAX_BACKUPS=7

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Create new backup
BACKUP_FILE="$BACKUP_DIR/config-$(date +%Y%m%d).tar.gz"
tar czf "$BACKUP_FILE" /etc/config/ 2>/dev/null

if [ $? -eq 0 ]; then
    logger -t auto-backup "Config backup completed: $BACKUP_FILE"
else
    logger -t auto-backup "ERROR: Config backup failed"
    exit 1
fi

# Remove backups older than MAX_BACKUPS days
find "$BACKUP_DIR" -name 'config-*.tar.gz' -mtime +$MAX_BACKUPS -delete

# Log retention status
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/config-*.tar.gz 2>/dev/null | wc -l)
logger -t auto-backup "Retention: $BACKUP_COUNT backups (max: $MAX_BACKUPS days)"
