#!/usr/bin/env bash
# ==============================================================================
# WordPress Multi-Site Smart Backup
# Optimized for 1GB VPS
# Backups: DB + wp-content only
# Upload: rclone (Google Drive / crypt remote)
# Retention: keep last 3 backups per site
# ==============================================================================

set -euo pipefail

### CONFIGURATION ##############################################################

BASE_WWW="/var/www"
REMOTE="gdrive-crypt:WP-Backups"
RETENTION=3
LOG_FILE="/var/log/wp-multisite-backup.log"
TMP_BASE="/tmp/wp-backup"

################################################################################

DATE=$(date +%F-%H%M)
mkdir -p "$TMP_BASE"

log() {
    echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || {
        log "ERROR: $1 not found"
        exit 1
    }
}

health_check() {
    systemctl is-active --quiet mariadb || {
        log "ERROR: MariaDB is not running"
        exit 1
    }
}

backup_site() {

    SITE_PATH="$1"
    SITE_NAME=$(basename "$SITE_PATH")
    SITE_TMP="$TMP_BASE/$SITE_NAME-$DATE"

    if [ ! -f "$SITE_PATH/wp-config.php" ]; then
        return
    fi

    log "Backing up site: $SITE_NAME"

    mkdir -p "$SITE_TMP"

    # Extract DB credentials from wp-config.php
    DB_NAME=$(grep DB_NAME "$SITE_PATH/wp-config.php" | cut -d \' -f4)
    DB_USER=$(grep DB_USER "$SITE_PATH/wp-config.php" | cut -d \' -f4)
    DB_PASS=$(grep DB_PASSWORD "$SITE_PATH/wp-config.php" | cut -d \' -f4)

    # Dump DB (compressed directly)
    mysqldump --single-transaction --quick --lock-tables=false \
        -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        | gzip > "$SITE_TMP/db.sql.gz"

    # Archive wp-content only
    tar -czf "$SITE_TMP/wp-content.tar.gz" -C "$SITE_PATH" wp-content

    # Create final archive
    tar -czf "$TMP_BASE/$SITE_NAME-$DATE.tar.gz" -C "$TMP_BASE" "$SITE_NAME-$DATE"

    # Upload
    rclone copy "$TMP_BASE/$SITE_NAME-$DATE.tar.gz" \
        "$REMOTE/$SITE_NAME/" --transfers=1 --checkers=2

    # Cleanup local temp
    rm -rf "$SITE_TMP"
    rm -f "$TMP_BASE/$SITE_NAME-$DATE.tar.gz"

    # Retention policy
    rclone lsf "$REMOTE/$SITE_NAME/" --files-only --format tp \
        | sort -r \
        | tail -n +$((RETENTION+1)) \
        | while read old; do
            rclone delete "$REMOTE/$SITE_NAME/$old"
        done

    log "Completed: $SITE_NAME"
}

################################################################################
# MAIN
################################################################################

log "===== START BACKUP ====="

check_command mysqldump
check_command rclone
check_command tar
check_command gzip

health_check

for DIR in "$BASE_WWW"/*; do
    [ -d "$DIR" ] && backup_site "$DIR"
done

rm -rf "$TMP_BASE"

log "===== ALL DONE ====="
