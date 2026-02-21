#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Ram Watchdog for fresh Debian/Ubuntu VPS.
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# License: See GitHub repository for license details.
# -----------------------------------------------------------------------------

set -e

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
PATH=/usr/sbin:/usr/bin:/sbin:/bin

INSTALL_PATH="/usr/local/bin/server-autoheal"
LOG_FILE="/var/log/server-autoheal.log"
STATE_FILE="/var/run/server-autoheal.state"
CRON_SCHEDULE="*/5 * * * *"

RAM_WARN=80
RAM_CRIT=90
SWAP_WARN=20
SWAP_CRIT=40
COOLDOWN=600   # 10 minutes

info(){ echo -e "\e[34m$1\e[0m"; }
ok(){ echo -e "\e[32m[✔] $1\e[0m"; }

detect_php_service() {
    systemctl list-units --type=service --no-legend | \
    awk '{print $1}' | grep -E 'php.*fpm' | head -n1
}

PHP_SERVICE=$(detect_php_service)
NGINX_SERVICE="nginx"
DB_SERVICE="mariadb"

[ -z "$PHP_SERVICE" ] && PHP_SERVICE="php8.3-fpm"

# ==============================================================================
# Create main watchdog script
# ==============================================================================
info "Installing Enterprise Auto-Heal..."

cat > $INSTALL_PATH <<EOF
#!/usr/bin/env bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin

LOG="$LOG_FILE"
STATE="$STATE_FILE"

RAM_WARN=$RAM_WARN
RAM_CRIT=$RAM_CRIT
SWAP_WARN=$SWAP_WARN
SWAP_CRIT=$SWAP_CRIT
COOLDOWN=$COOLDOWN

PHP_SERVICE="$PHP_SERVICE"
NGINX_SERVICE="$NGINX_SERVICE"
DB_SERVICE="$DB_SERVICE"

log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') | \$1" >> \$LOG
}

cooldown_active() {
    [ -f "\$STATE" ] || return 1
    LAST=\$(cat \$STATE)
    NOW=\$(date +%s)
    DIFF=\$((NOW - LAST))
    [ "\$DIFF" -lt "\$COOLDOWN" ]
}

touch \$LOG

RAM_USED=\$(free | awk '/Mem:/ {printf("%.0f"), \$3/\$2 * 100}')
SWAP_USED=\$(free | awk '/Swap:/ {if (\$2==0) print 0; else printf("%.0f"), \$3/\$2 * 100}')

log "RAM=\${RAM_USED}% SWAP=\${SWAP_USED}%"

if cooldown_active; then
    log "Cooldown active. Skipping actions."
    exit 0
fi

# Warning
if [ "\$RAM_USED" -ge "\$RAM_WARN" ] || [ "\$SWAP_USED" -ge "\$SWAP_WARN" ]; then
    log "Warning threshold reached. Dropping caches."
    sync
    echo 3 > /proc/sys/vm/drop_caches
    sleep 3
fi

RAM_USED=\$(free | awk '/Mem:/ {printf("%.0f"), \$3/\$2 * 100}')
SWAP_USED=\$(free | awk '/Swap:/ {if (\$2==0) print 0; else printf("%.0f"), \$3/\$2 * 100}')

# Critical
if [ "\$RAM_USED" -ge "\$RAM_CRIT" ] || [ "\$SWAP_USED" -ge "\$SWAP_CRIT" ]; then

    log "Critical memory detected."

    systemctl reload \$PHP_SERVICE 2>/dev/null || true
    sleep 5

    RAM_AFTER=\$(free | awk '/Mem:/ {printf("%.0f"), \$3/\$2 * 100}')

    if [ "\$RAM_AFTER" -ge "\$RAM_CRIT" ]; then
        log "Restarting PHP-FPM."
        systemctl restart \$PHP_SERVICE
        sleep 8
    fi

    RAM_AFTER=\$(free | awk '/Mem:/ {printf("%.0f"), \$3/\$2 * 100}')

    if [ "\$RAM_AFTER" -ge "\$RAM_CRIT" ]; then
        log "Restarting Nginx."
        systemctl restart \$NGINX_SERVICE
        sleep 5
    fi

    RAM_AFTER=\$(free | awk '/Mem:/ {printf("%.0f"), \$3/\$2 * 100}')

    if [ "\$RAM_AFTER" -ge 95 ]; then
        log "Extreme condition. Restarting MariaDB."
        systemctl restart \$DB_SERVICE
    fi

    date +%s > \$STATE
fi
EOF

chmod +x $INSTALL_PATH
ok "Auto-Heal binary installed."

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
