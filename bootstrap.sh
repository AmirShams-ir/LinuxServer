#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: This script performs mandatory base initialization on a fresh
#              Linux VPS. It prepares the system with safe defaults, essential
#              tools, and baseline optimizations before any role-specific
#              configuration (hosting, security, WordPress, etc.).
#
# Author: BabyBoss
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
# Logging (lightweight & optional)
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
# OS validation (Ubuntu & Debian)
# --------------------------------------------------
if ! grep -Eqi '^(ID=(ubuntu|debian)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "ERROR: This script supports Debian-based systems only (Ubuntu / Debian)."
  exit 1
fi

# --------------------------------------------------
# Timezone & Locale
# --------------------------------------------------
echo "[*] Timezone configuration"
echo "    Recommendation: UTC (best for logs & servers)"

read -rp "Set timezone to UTC? [Y/n]: " TZ_CHOICE
TZ_CHOICE=${TZ_CHOICE:-Y}

if [[ "$TZ_CHOICE" =~ ^[Yy]$ ]]; then
  if has_systemd; then
    timedatectl set-timezone UTC
    echo "[+] Timezone set to UTC"
  else
    echo "[!] systemd not available, skipping timezone"
  fi
else
  read -rp "Enter custom timezone (e.g. Asia/Tehran): " TZ
  if [[ -n "$TZ" && has_systemd ]]; then
    timedatectl set-timezone "$TZ"
    echo "[+] Timezone set to $TZ"
  else
    echo "[*] Timezone unchanged"
  fi
fi

  read -rp "Enter locale (e.g. en_US.UTF-8, fa_IR.UTF-8) [skip]: " LOCALE
  if [[ -n "$LOCALE" ]]; then
    locale-gen "$LOCALE"
    update-locale LANG="$LOCALE"
    echo "[+] Locale set to $LOCALE"
  else
    echo "[*] Locale skipped"
  fi
else
  echo "[*] Timezone & locale left unchanged"
fi

# --------------------------------------------------
# Base system update
# --------------------------------------------------
echo "[*] Updating base system..."
apt update -y
apt upgrade -y
apt autoremove -y
apt autoclean -y

# --------------------------------------------------
# Essential packages (minimal & universal)
# --------------------------------------------------
echo "[*] Installing essential packages..."
apt install -y \
  sudo \
  curl \
  wget \
  ca-certificates \
  gnupg \
  lsb-release \
  dialog \
  unzip \
  htop \
  net-tools \
  bash-completion \
  software-properties-common

# --------------------------------------------------
# Swap creation (safe & adaptive)
# --------------------------------------------------
echo "[*] Checking swap..."
if ! swapon --show | grep -q swap; then
  RAM_MB=$(free -m | awk '/Mem:/ {print $2}')

  if [[ "$RAM_MB" -lt 2048 ]]; then
    SWAP_SIZE="2G"
  else
    SWAP_SIZE="1G"
  fi

  echo "[*] Creating swap file ($SWAP_SIZE)..."
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile

  if ! grep -q "/swapfile" /etc/fstab; then
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
  fi
else
  echo "[*] Swap already exists. Skipping."
fi

# --------------------------------------------------
# Safe sysctl baseline (non-aggressive)
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
# Journald log limits
# --------------------------------------------------
echo "[*] Limiting journald disk usage..."
mkdir -p /etc/systemd/journald.conf.d

cat <<EOF >/etc/systemd/journald.conf.d/limit.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
EOF

systemctl restart systemd-journald

# --------------------------------------------------
# Optional: automatic security updates
# --------------------------------------------------
read -rp "Enable automatic security updates (unattended-upgrades)? [y/N]: " AUTO
if [[ "$AUTO" =~ ^[Yy]$ ]]; then
  echo "[*] Enabling unattended-upgrades..."
  apt install -y unattended-upgrades
  dpkg-reconfigure -f noninteractive unattended-upgrades
else
  echo "[*] Automatic updates skipped."
fi

# --------------------------------------------------
# Done
# --------------------------------------------------
echo "=================================================="
echo " Bootstrap completed successfully"
echo " You can now run any One-click profile"
echo "=================================================="
