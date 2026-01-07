#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: This script performs mandatory base initialization on a fresh
#              Linux VPS. It prepares the system with safe defaults, essential
#              tools, and baseline optimizations before any role-specific
#              configuration (hosting, security, WordPress, etc.).
#
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
#
# Disclaimer: This script is provided for educational and informational
#             purposes only. Use it responsibly and in compliance with all
#             applicable laws and regulations.
#
# Note: This script is designed to be SAFE, IDEMPOTENT, and NON-DESTRUCTIVE.
#       Review before use. No application-level services are installed here.
# -----------------------------------------------------------------------------

set -euo pipefail

# --------------------------------------------------
# Logging
# --------------------------------------------------
LOG="/var/log/server-bootstrap.log"
if touch "$LOG" &>/dev/null; then
  exec > >(tee -a "$LOG") 2>&1
  echo "[*] Logging enabled: $LOG"
fi

echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Bootstrap Script Started\e[0m"
echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"

# --------------------------------------------------
# Root / sudo handling
# --------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Re-running script with sudo..."
    exec sudo bash "$0" "$@"
  else
    echo "Error: Root privileges required."
    exit 1
  fi
fi

# --------------------------------------------------
# Helper: systemd detection
# --------------------------------------------------
has_systemd() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

# --------------------------------------------------
# Status flags (for final report)
# --------------------------------------------------
STATUS_TIMEZONE=false
STATUS_LOCALE=false
STATUS_UPDATE=false
STATUS_PACKAGES=false
STATUS_SWAP=false
STATUS_SYSCTL=false
STATUS_JOURNALD=false
STATUS_AUTOUPDATE=false
STATUS_BBR=false

# --------------------------------------------------
# OS validation
# --------------------------------------------------
if ! grep -Eqi '^(ID=(ubuntu|debian)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "ERROR: Debian/Ubuntu only."
  exit 1
fi

# --------------------------------------------------
# Timezone & Locale (FORCED)
# --------------------------------------------------
echo "[*] Configuring timezone & locale..."

if has_systemd; then
  CURRENT_TZ="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  [[ "$CURRENT_TZ" != "UTC" ]] && timedatectl set-timezone UTC
  STATUS_TIMEZONE=true
fi

LOCALE="en_US.UTF-8"
if ! locale -a | grep -qx "$LOCALE"; then
  sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen "$LOCALE"
fi
update-locale LANG="$LOCALE" LC_ALL="$LOCALE"
export LANG="$LOCALE" LC_ALL="$LOCALE"
STATUS_LOCALE=true

# --------------------------------------------------
# Base system update
# --------------------------------------------------
echo "[*] Updating system..."
apt update -y
apt upgrade -y
apt autoremove -y
apt autoclean -y
STATUS_UPDATE=true

# --------------------------------------------------
# Essential packages + unattended-upgrades
# --------------------------------------------------
echo "[*] Installing essential packages..."
apt install -y \
  sudo curl wget git dialog ca-certificates gnupg lsb-release \
  htop zip unzip net-tools openssl build-essential \
  bash-completion unattended-upgrades autoremove autoclean 
STATUS_PACKAGES=true

echo "[*] Enabling automatic security updates..."
dpkg-reconfigure -f noninteractive unattended-upgrades
STATUS_AUTOUPDATE=true

# --------------------------------------------------
# Swap (adaptive)
# --------------------------------------------------
echo "[*] Checking swap..."
if ! swapon --show | grep -q swap; then
  RAM_MB="$(free -m | awk '/Mem:/ {print $2}')"
  [[ "$RAM_MB" -lt 2048 ]] && SWAP_SIZE="2G" || SWAP_SIZE="1G"

  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
STATUS_SWAP=true

# --------------------------------------------------
# Sysctl baseline
# --------------------------------------------------
cat <<EOF >/etc/sysctl.d/99-bootstrap.conf
vm.swappiness=10
fs.file-max=100000
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
EOF

sysctl --system >/dev/null
STATUS_SYSCTL=true

# --------------------------------------------------
# TCP BBR
# --------------------------------------------------
echo "[*] Configuring TCP BBR..."
modprobe tcp_bbr
if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
  cat <<EOF >/etc/sysctl.d/99-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null
  STATUS_BBR=true
fi

# --------------------------------------------------
# Journald limits
# --------------------------------------------------
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF >/etc/systemd/journald.conf.d/limit.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
EOF

has_systemd && systemctl restart systemd-journald
STATUS_JOURNALD=true

# --------------------------------------------------
# Final Report
# --------------------------------------------------
report() {
  local label="$1" status="$2"
  if [[ "$status" == true ]]; then
    printf "  %-34s \e[32m[ OK ]\e[0m\n" "$label"
  else
    printf "  %-34s \e[33m[ SKIPPED ]\e[0m\n" "$label"
  fi
}

echo
echo -e "\e[36m==================================================\e[0m"
echo -e "\e[1m               BOOTSTRAP EXECUTION REPORT\e[0m"
echo -e "\e[36m==================================================\e[0m"
report "Timezone configuration"        "$STATUS_TIMEZONE"
report "Locale configuration"          "$STATUS_LOCALE"
report "System update & upgrade"       "$STATUS_UPDATE"
report "Essential packages"            "$STATUS_PACKAGES"
report "Swap configuration"            "$STATUS_SWAP"
report "Sysctl baseline"               "$STATUS_SYSCTL"
report "Journald limits"               "$STATUS_JOURNALD"
report "Automatic security updates"    "$STATUS_AUTOUPDATE"
report "TCP BBR congestion control"    "$STATUS_BBR"

echo
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;32m✔ Bootstrap completed successfully\e[0m"
echo -e " \e[1;32m✔ System is clean, updated & production-ready\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo

# --------------------------------------------------
# Cleanup (safe mode)
# --------------------------------------------------
unset LOG
unset CURRENT_TZ
unset LOCALE
unset RAM_MB
unset SWAP_SIZE
unset LOG CURRENT_TZ LOCALE RAM_MB SWAP_SIZE
unset STATUS_TIMEZONE STATUS_LOCALE STATUS_UPDATE STATUS_PACKAGES
unset STATUS_SWAP STATUS_SYSCTL STATUS_JOURNALD STATUS_AUTOUPDATE STATUS_BBR
rm bootstrap.sh
