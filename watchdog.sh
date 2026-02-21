#!/usr/bin/env bash

# ==============================
# Smart RAM Watchdog Installer
# ==============================

INSTALL_PATH="/usr/local/bin/ram-watchdog"
LOG_FILE="/var/log/ram-watchdog.log"
CRON_SCHEDULE="*/5 * * * *"
RAM_THRESHOLD=85
SWAP_THRESHOLD=25

echo "Installing Smart RAM Watchdog..."

# ------------------------------
# Create main watchdog script
# ------------------------------

cat > $INSTALL_PATH <<'EOF'
#!/usr/bin/env bash

LOG="/var/log/ram-watchdog.log"
RAM_THRESHOLD=85
SWAP_THRESHOLD=25

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG
}

RAM_USED=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
SWAP_USED=$(free | awk '/Swap:/ {if ($2==0) print 0; else printf("%.0f"), $3/$2 * 100}')

log "RAM: ${RAM_USED}% | SWAP: ${SWAP_USED}%"

if [ "$RAM_USED" -ge "$RAM_THRESHOLD" ] || [ "$SWAP_USED" -ge "$SWAP_THRESHOLD" ]; then

    log "High memory detected. Dropping cache..."
    sync
    echo 1 > /proc/sys/vm/drop_caches
    sleep 3

    RAM_AFTER=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
    SWAP_AFTER=$(free | awk '/Swap:/ {if ($2==0) print 0; else printf("%.0f"), $3/$2 * 100}')

    log "After cache drop → RAM: ${RAM_AFTER}% | SWAP: ${SWAP_AFTER}%"

    if [ "$RAM_AFTER" -ge "$RAM_THRESHOLD" ] || [ "$SWAP_AFTER" -ge "$SWAP_THRESHOLD" ]; then

        # Find heaviest php-fpm process
        PID=$(ps -eo pid,comm,%mem --sort=-%mem | \
              grep php-fpm | head -n 1 | awk '{print $1}')

        if [ ! -z "$PID" ]; then
            log "Gracefully killing PHP-FPM PID $PID"
            kill $PID
            sleep 5

            if ps -p $PID > /dev/null 2>&1; then
                log "Force killing PHP-FPM PID $PID"
                kill -9 $PID
            fi
        else
            log "No PHP-FPM process found."
        fi
    fi
fi
EOF

chmod +x $INSTALL_PATH

# ------------------------------
# Setup cron safely (no duplicate)
# ------------------------------

( crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" ; \
  echo "$CRON_SCHEDULE $INSTALL_PATH" ) | crontab -

echo "--------------------------------------"
echo "Installed at: $INSTALL_PATH"
echo "Log file: $LOG_FILE"
echo "Cron: every 5 minutes"
echo "--------------------------------------"
echo "Done."
