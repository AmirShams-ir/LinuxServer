#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: This script performs mandatory base hosting setup on a fresh
#              Linux VPS.
#
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
#
# License: See GitHub repository for license details.
#
# Disclaimer: This script is provided for educational and informational
#             purposes only. Use it responsibly and in compliance with all
#             applicable laws and regulations.
#
# Note: This script is designed to be SAFE, IDEMPOTENT, and NON-DESTRUCTIVE.
#       Review before use. No application-level services are installed here.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Root / sudo handling
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo --preserve-env=PATH bash "$0" "$@"
  else
    printf "This script requires root privileges.\n"
    exit 1
  fi
fi

# ==============================================================================
# OS validation
# ==============================================================================
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
else
  printf "ERROR: Cannot detect OS.\n"
  exit 1
fi

if [[ "${ID}" != "debian" && "${ID}" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then
  printf "ERROR: Debian/Ubuntu only.\n"
  exit 1
fi

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
# Helper Functions
# ==============================================================================
info() { printf "\e[34m%s\e[0m\n" "$*"; }
rept() { printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn() { printf "\e[33m[!] %s\e[0m\n" "$*"; }
die()  { printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Bootstrap Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Helper: systemd detection
# ==============================================================================
has_systemd() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

# ==============================================================================
# Status flags
# ==============================================================================
STATUS_TIMEZONE=false
STATUS_LOCALE=false
STATUS_UPDATE=false
STATUS_PACKAGES=false
STATUS_SWAP=false
STATUS_SYSCTL=false
STATUS_JOURNALD=false
STATUS_AUTOUPDATE=false
STATUS_BBR=false

# ==============================================================================
# Timezone & Locale
# ==============================================================================
info "Configuring timezone & locale..."

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

# ==============================================================================
# System Update
# ==============================================================================
info "Updating system..."
apt update -y
apt upgrade -y
apt autoremove -y
apt autoclean -y
STATUS_UPDATE=true

# ==============================================================================
# Essential Packages
# ==============================================================================
info "Installing essential packages..."
apt install -y \
  sudo curl wget git dialog ca-certificates gnupg lsb-release \
  htop zip unzip net-tools openssl build-essential \
  bash-completion unattended-upgrades

STATUS_PACKAGES=true

info "Enabling automatic security updates..."
dpkg-reconfigure -f noninteractive unattended-upgrades
STATUS_AUTOUPDATE=true

# ==============================================================================
# Swap
# ==============================================================================
info "Checking swap..."

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

# ==============================================================================
# Sysctl Baseline
# ==============================================================================
info "Applying sysctl baseline..."

cat <<EOF >/etc/sysctl.d/99-bootstrap.conf
vm.swappiness=10
fs.file-max=100000
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
EOF

sysctl --system >/dev/null
STATUS_SYSCTL=true

# ==============================================================================
# TCP BBR
# ==============================================================================
info "Configuring TCP BBR..."

modprobe tcp_bbr || true

if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
  cat <<EOF >/etc/sysctl.d/99-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null
  STATUS_BBR=true
else
  warn "BBR not supported on this kernel"
fi

# ==============================================================================
# Journald Limits
# ==============================================================================
info "Configuring journald limits..."

mkdir -p /etc/systemd/journald.conf.d

cat <<EOF >/etc/systemd/journald.conf.d/limit.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
EOF

has_systemd && systemctl restart systemd-journald
STATUS_JOURNALD=true

# ==============================================================================
# Final Report
# ==============================================================================
report() {
  local label="$1" status="$2"
  if [[ "$status" == true ]]; then
    rept "$label"
  else
    warn "$label (skipped)"
  fi
}

info "=================================================="
info "BOOTSTRAP EXECUTION REPORT"
info "=================================================="

report "Timezone configuration"        "$STATUS_TIMEZONE"
report "Locale configuration"          "$STATUS_LOCALE"
report "System update & upgrade"       "$STATUS_UPDATE"
report "Essential packages"            "$STATUS_PACKAGES"
report "Swap configuration"            "$STATUS_SWAP"
report "Sysctl baseline"               "$STATUS_SYSCTL"
report "Journald limits"               "$STATUS_JOURNALD"
report "Automatic security updates"    "$STATUS_AUTOUPDATE"
report "TCP BBR congestion control"    "$STATUS_BBR"

info "══════════════════════════════════════════════════"
rept "Bootstrap completed successfully"
rept "System is clean, updated & production-ready"
info "══════════════════════════════════════════════════"

# ==============================================================================
# Cleanup
# ==============================================================================
unset LOG CURRENT_TZ LOCALE RAM_MB SWAP_SIZE
unset STATUS_TIMEZONE STATUS_LOCALE STATUS_UPDATE STATUS_PACKAGES
unset STATUS_SWAP STATUS_SYSCTL STATUS_JOURNALD STATUS_AUTOUPDATE STATUS_BBR
