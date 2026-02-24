#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Autoheal Enterprise Installer (Stable • Self-Healing • Production)
# Supports: Debian 12/13, Ubuntu 22.04/24.04
# Author: Amir Shams
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ========================= Root Checker =========================
if [[ $EUID -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi

# ========================= Helper ===============================
info(){ printf "\e[34m%s\e[0m\n" "$*"; }
ok(){   printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn(){ printf "\e[33m[!] %s\e[0m\n" "$*"; }
die(){  printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }

# ========================= OS Validation =========================
source /etc/os-release || die "Cannot detect OS"
case "$ID" in
  debian) [[ "$VERSION_ID" == "12" || "$VERSION_ID" == "13" ]] || die "Unsupported Debian";;
  ubuntu) [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]] || die "Unsupported Ubuntu";;
  *) die "Unsupported OS";;
esac
ok "OS: $PRETTY_NAME"

info "═══════════════════════════════════════════"
info "✔ Auto Heal Script Installation"
info "═══════════════════════════════════════════"

# ========================= Earlyoom =========================
apt install earlyoom
systemctl enable earlyoom
systemctl start earlyoom

# ========================= Varibles =========================
INSTALL_PATH="/usr/local/bin/enterprise-autoheal"
SERVICE_PATH="/etc/systemd/system/enterprise-autoheal.service"
TIMER_PATH="/etc/systemd/system/enterprise-autoheal.timer"
LOG_FILE="/var/log/enterprise-autoheal.log"

RAM_WARN=75
RAM_CRIT=85
RAM_EMERG=92
LOAD_WARN=2.0
LOAD_CRIT=4.0
COOLDOWN=300

# ========================= Uninstall =========================
if [[ "${1:-}" == "uninstall" ]]; then
  systemctl stop enterprise-autoheal.timer || true
  systemctl disable enterprise-autoheal.timer || true
  rm -f "$SERVICE_PATH" "$TIMER_PATH" "$INSTALL_PATH"
  systemctl daemon-reload
  ok "Enterprise Auto-Heal Removed"
  exit 0
fi

info "Installing dependencies..."
apt update -y >/dev/null 2>&1 || true
apt install -y bc curl >/dev/null 2>&1 || true

# ========================= Core Binary =========================
cat > "$INSTALL_PATH" <<EOF
#!/usr/bin/env bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin

LOG="$LOG_FILE"
STATE="/var/run/enterprise-autoheal.state"

RAM_WARN=$RAM_WARN
RAM_CRIT=$RAM_CRIT
RAM_EMERG=$RAM_EMERG
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

touch "\$LOG"

RAM=\$(ram_usage)
SWAP=\$(swap_usage)
LOAD=\$(load_avg)

log "RAM=\${RAM}% SWAP=\${SWAP}% LOAD=\${LOAD}"

if cooldown; then
  log "Cooldown active"
  exit 0
fi

# ---------------- Warning Stage ----------------
if (( RAM >= RAM_WARN )) || (( \$(echo "\$LOAD > \$LOAD_WARN" | bc -l) )); then
  log "Warning: Dropping caches"
  sync
  sysctl -w vm.drop_caches=3 >/dev/null 2>&1 || true
fi

RAM=\$(ram_usage)
LOAD=\$(load_avg)

# ---------------- Critical Stage ----------------
if (( RAM >= RAM_CRIT )) || (( \$(echo "\$LOAD > \$LOAD_CRIT" | bc -l) )); then
  log "Critical: Restarting PHP-FPM"
  if [[ -n "\$PHP_SERVICE" ]]; then
    systemctl restart "\$PHP_SERVICE" 2>/dev/null || true
  fi
  sleep 5
fi

RAM=\$(ram_usage)

# ---------------- Emergency Stage ----------------
if (( RAM >= RAM_EMERG )); then
  PID=\$(top_memory_pid)
  if [[ -n "\$PID" ]]; then
    log "Emergency: Killing PID \$PID"
    kill -9 "\$PID" 2>/dev/null || true
    sleep 3
  fi
fi

RAM=\$(ram_usage)

# ---------------- Absolute Meltdown ----------------
if (( RAM >= 95 )); then
  log "Extreme meltdown. Rebooting."
  date +%s > "\$STATE"
  systemctl reboot --force
fi

date +%s > "\$STATE"
EOF

chmod +x "$INSTALL_PATH"

# ========================= Service =========================
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Enterprise Auto-Heal
After=network.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

# ========================= Timer =========================
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run Enterprise Auto-Heal every 2 minutes

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

info "═══════════════════════════════════════════"
ok "Enterprise Auto-Heal Installed Successfully"
ok "Binary: $INSTALL_PATH"
ok "Log: $LOG_FILE"
ok "Status: systemctl status enterprise-autoheal.timer"
info "═══════════════════════════════════════════"
