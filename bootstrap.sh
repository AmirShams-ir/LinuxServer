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
# Root / sudo handling (smart escalation)
# --------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Re-running script with sudo..."
    exec sudo bash "$0" "$@"
  else
    echo "Error: Root privileges required and sudo not available."
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
# Logging
# --------------------------------------------------
LOG="/var/log/server-bootstrap.log"
if touch "$LOG" &>/dev/null; then
  exec > >(tee -a "$LOG") 2>&1
  echo "[*] Logging enabled: $LOG"
else
  echo "[!] Logging disabled (no write access to /var/log)"
fi

echo "=================================================="
echo " Server Bootstrap Started"
echo "=================================================="

# --------------------------------------------------
# OS validation (Debian / Ubuntu)
# --------------------------------------------------
if ! grep -Eqi '^(ID=(ubuntu|debian)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "ERROR: This script supports Debian-based systems only."
  exit 1
fi

# --------------------------------------------------
# Timezone & Locale (FORCED)
# --------------------------------------------------
echo "[*] Configuring timezone and locale (UTC / en_US.UTF-8)"

if has_systemd; then
  CURRENT_TZ="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  if [[ "$CURRENT_TZ" != "UTC" ]]; then
    timedatectl set-timezone UTC
    echo "[+] Timezone set to UTC"
  else
    echo "[*] Timezone already UTC"
  fi
else
  echo "[!] systemd not available, skipping timezone"
fi

LOCALE="en_US.UTF-8"
if ! locale -a | grep -qx "$LOCALE"; then
  echo "[*] Generating locale $LOCALE"
  sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen "$LOCALE"
else
  echo "[*] Locale $LOCALE already exists"
fi

update-locale LANG="$LOCALE" LC_ALL="$LOCALE"
export LANG="$LOCALE"
export LC_ALL="$LOCALE"

# --------------------------------------------------
# Base system update
# --------------------------------------------------
echo "[*] Updating base system..."
apt update -y
apt upgrade -y
apt autoremove -y
apt autoclean -y

# --------------------------------------------------
# Essential packages
# --------------------------------------------------
echo "[*] Installing essential packages..."
apt install -y \
  sudo \
  curl \
  wget \
  git \
  ca-certificates \
  gnupg \
  lsb-release \
  htop \
  zip \
  unzip \
  net-tools \
  openssl \
  build-essential \
  bash-completion \
  unattended-upgrades

# --------------------------------------------------
# Automatic security updates (FORCED)
# --------------------------------------------------
echo "[*] Enabling unattended security upgrades..."
dpkg-reconfigure -f noninteractive unattended-upgrades

# --------------------------------------------------
# Swap creation (adaptive)
# --------------------------------------------------
echo "[*] Checking swap..."
if ! swapon --show | grep -q swap; then
  RAM_MB="$(free -m | awk '/Mem:/ {print $2}')"

  if [[ "$RAM_MB" -lt 2048 ]]; then
    SWAP_SIZE="2G"
  else
    SWAP_SIZE="1G"
  fi

  echo "[*] Creating swap ($SWAP_SIZE)..."
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile

  grep -q "/swapfile" /etc/fstab || \
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
else
  echo "[*] Swap already exists"
fi

# --------------------------------------------------
# Sysctl baseline
# --------------------------------------------------
echo "[*] Applying sysctl baseline..."
cat <<EOF >/etc/sysctl.d/99-bootstrap.conf
vm.swappiness=10
fs.file-max=100000
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
EOF

sysctl --system

# --------------------------------------------------
# Journald limits
# --------------------------------------------------
echo "[*] Limiting journald disk usage..."
mkdir -p /etc/systemd/journald.conf.d

cat <<EOF >/etc/systemd/journald.conf.d/limit.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
EOF

if has_systemd; then
  systemctl restart systemd-journald
fi

# --------------------------------------------------
# Cleanup (FULL – paranoia mode 😄)
# --------------------------------------------------
unset LOG
unset CURRENT_TZ
unset LOCALE
unset RAM_MB
unset SWAP_SIZE

# --------------------------------------------------
# Done
# --------------------------------------------------
echo "=================================================="
echo " Bootstrap completed successfully"
echo " System is clean, predictable, and production-ready"
echo "=================================================="