#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Ram Watchdog for fresh Debian/Ubuntu VPS.
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# License: See GitHub repository for license details.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Root
# ==============================================================================
if [[ $EUID -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi

info(){ printf "\e[34m%s\e[0m\n" "$*"; }
ok(){ printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn(){ printf "\e[33m[!] %s\e[0m\n" "$*"; }
die(){ printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }
has_systemd(){ [[ -d /run/systemd/system ]]; }

# ==============================================================================
# OS Validation
# ==============================================================================
source /etc/os-release || die "Cannot detect OS"

case "$ID" in
  debian) [[ "$VERSION_ID" == "12" || "$VERSION_ID" == "13" ]] || die "Unsupported Debian";;
  ubuntu) [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]] || die "Unsupported Ubuntu";;
  *) die "Unsupported OS";;
esac

ok "OS: $PRETTY_NAME"

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/server-$(basename "$0" .sh).log"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"

{
  printf "============================================================\n"
  printf " Script: %s\n" "$(basename "$0")"
  printf " Started at: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf " Hostname: %s\n" "$(hostname)"
  printf "============================================================\n"
} >> "$LOG"

exec > >(tee -a "$LOG") 2> >(tee -a "$LOG" >&2)

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Ram Watchdog Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Smart RAM Watchdog Installer
# ==============================================================================
INSTALL_PATH="/usr/local/bin/ram-watchdog"
LOG_FILE="/var/log/ram-watchdog.log"
CRON_SCHEDULE="*/5 * * * *"
RAM_THRESHOLD=90
SWAP_THRESHOLD=30

# ==============================================================================
# Create main watchdog script
# ==============================================================================
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
ok "RAM Watchdog Created"

# ==============================================================================
# Setup cron safely
# ==============================================================================
( crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" ; \
  echo "$CRON_SCHEDULE $INSTALL_PATH" ) | crontab -
ok "Corn Job Created"

# ==============================================================================
# Final
# ==============================================================================
info "═══════════════════════════════════════════"
ok "Installed at: $INSTALL_PATH"
ok "Log file: $LOG_FILE"
ok "Cron: every 5 minutes"
info "═══════════════════════════════════════════"
