#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Autoheal for Debian/Ubuntu VPS.
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# License: See GitHub repository for license details.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Root Handling
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo --preserve-env=PATH bash "$0" "$@"
  else
    printf "Root privileges required.\n"
    exit 1
  fi
fi

# ==============================================================================
# OS Validation
# ==============================================================================
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
else
  printf "Cannot detect OS.\n"
  exit 1
fi

[[ "${ID}" == "debian" || "${ID}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* ]] \
  || { printf "Debian/Ubuntu only.\n"; exit 1; }

# ==============================================================================
# Helpers
# ==============================================================================
info(){ printf "\e[34m%s\e[0m\n" "$*"; }
ok(){   printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn(){ printf "\e[33m[!] %s\e[0m\n" "$*"; }
die(){  printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Auto Heal Script Installation"
info "═══════════════════════════════════════════"

# ==============================================================================
# Install Earlyoom
# ==============================================================================
apt install earlyoom
systemctl enable earlyoom
systemctl start earlyoom

# ==============================================================================
# Variables
# ==============================================================================
INSTALL_PATH="/usr/local/bin/enterprise-autoheal"
SERVICE_PATH="/etc/systemd/system/enterprise-autoheal.service"
TIMER_PATH="/etc/systemd/system/enterprise-autoheal.timer"
LOG_FILE="/var/log/enterprise-autoheal.log"

RAM_WARN=75
RAM_CRIT=85
RAM_EMERG=92

SWAP_WARN=30
SWAP_CRIT=50

LOAD_WARN=2.0
LOAD_CRIT=4.0

COOLDOWN=300

# ==============================================================================
# Dependency
# ==============================================================================
apt update -y >/dev/null 2>&1 || true
apt install -y bc >/dev/null 2>&1 || true

# ==============================================================================
# Install Autoheal
# ==============================================================================
cat > "$INSTALL_PATH" <<EOF
#!/usr/bin/env bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin

LOG="$LOG_FILE"
STATE="/var/run/enterprise-autoheal.state"

RAM_WARN=$RAM_WARN
RAM_CRIT=$RAM_CRIT
RAM_EMERG=$RAM_EMERG
SWAP_WARN=$SWAP_WARN
SWAP_CRIT=$SWAP_CRIT
LOAD_WARN=$LOAD_WARN
LOAD_CRIT=$LOAD_CRIT
COOLDOWN=$COOLDOWN

command -v bc >/dev/null 2>&1 || exit 0

log(){ echo "\$(date '+%F %T') | \$1" >> "\$LOG"; }

cooldown(){
  [[ -f "\$STATE" ]] || return 1
  LAST=\$(cat "\$STATE")
  NOW=\$(date +%s)
  [[ \$((NOW-LAST)) -lt \$COOLDOWN ]]
}

ram_usage(){ free | awk '/Mem:/ {printf("%.0f"), \$3/\$2 * 100}'; }
swap_usage(){ free | awk '/Swap:/ {if (\$2==0) print 0; else printf("%.0f"), \$3/\$2 * 100}'; }
load_avg(){ awk '{print \$1}' /proc/loadavg; }
top_memory_pid(){ ps -eo pid,%mem --sort=-%mem | awk 'NR==2 {print \$1}'; }

PHP_SERVICE=\$(systemctl list-units --type=service --no-legend | awk '{print \$1}' | grep -E 'php.*fpm' | head -n1)
DB_SERVICE="mariadb"

touch "\$LOG"

RAM=\$(ram_usage)
SWAP=\$(swap_usage)
LOAD=\$(load_avg)

log "RAM=\${RAM}% SWAP=\${SWAP}% LOAD=\${LOAD}"

if cooldown; then
  log "Cooldown active"
  exit 0
fi

# ================= Warning =================
if (( RAM >= RAM_WARN )) || (( SWAP >= SWAP_WARN )) || (( \$(echo "\$LOAD > \$LOAD_WARN" | bc -l) )); then
  log "Warning: Dropping caches"
  sync
  sysctl -w vm.drop_caches=3 >/dev/null 2>&1 || true
fi

RAM=\$(ram_usage)
SWAP=\$(swap_usage)

# ================= Critical =================
if (( RAM >= RAM_CRIT )) || (( SWAP >= SWAP_CRIT )) || (( \$(echo "\$LOAD > \$LOAD_CRIT" | bc -l) )); then
  log "Critical: Restarting PHP-FPM"
  if [[ -n "\$PHP_SERVICE" ]]; then
    systemctl restart "\$PHP_SERVICE" 2>/dev/null || true
  fi
  sleep 5
fi

RAM=\$(ram_usage)
SWAP=\$(swap_usage)

# ================= MariaDB Graceful Protection =================
if (( RAM >= RAM_CRIT )) && (( SWAP >= SWAP_WARN )); then
  log "High RAM + Swap detected: Flushing MariaDB"

  # Try graceful flush
  mysqladmin flush-tables >/dev/null 2>&1 || true
  mysqladmin flush-logs >/dev/null 2>&1 || true

  sleep 3

  RAM_AFTER=\$(ram_usage)

  if (( RAM_AFTER >= RAM_CRIT )); then
    log "Restarting MariaDB gracefully"
    systemctl restart "\$DB_SERVICE" 2>/dev/null || true
    sleep 8
  fi
fi

RAM=\$(ram_usage)

# ================= Emergency Kill =================
if (( RAM >= RAM_EMERG )); then
  PID=\$(top_memory_pid)
  if [[ -n "\$PID" ]]; then
    log "Emergency: Killing PID \$PID"
    kill -9 "\$PID" 2>/dev/null || true
    sleep 3
  fi
fi

RAM=\$(ram_usage)

# ================= Absolute Meltdown =================
if (( RAM >= 95 )); then
  log "Extreme meltdown. Rebooting system."
  date +%s > "\$STATE"
  systemctl reboot --force
fi

date +%s > "\$STATE"
EOF

chmod +x "$INSTALL_PATH"

# ==============================================================================
# Service
# ==============================================================================
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Enterprise AutoHeal++

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

# ==============================================================================
# Timer
# ==============================================================================
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run Enterprise AutoHeal every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable enterprise-autoheal.timer
systemctl start enterprise-autoheal.timer

touch "$LOG_FILE"

# ==============================================================================
# Final
# ==============================================================================
info "═══════════════════════════════════════════"
ok "Enterprise AutoHeal Installed Successfully"
ok "Log: $LOG_FILE"
ok "Installed at: $INSTALL_PATH"
info "═══════════════════════════════════════════"
