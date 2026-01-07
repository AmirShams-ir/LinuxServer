#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: This script performs mandatory base hosting setup on a fresh
#              Linux VPS.
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
LOG="/var/log/server-security.log"
if touch "$LOG" &>/dev/null; then
  exec > >(tee -a "$LOG") 2>&1
  echo "[*] Logging enabled: $LOG"
fi

echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Security Setup Script Started\e[0m"
echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"

# --------------------------------------------------
# Root / sudo handling
# --------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo bash "$0" "$@"
  else
    echo "ERROR: Root privileges required."
    exit 1
  fi
fi

# --------------------------------------------------
# OS validation
# --------------------------------------------------
if ! grep -Eqi '^(ID=(ubuntu|debian)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "ERROR: Debian/Ubuntu only."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ==================================================
# HELPERS
# ==================================================
log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ==================================================
# CONFIG
# ==================================================
SSH_PORT=22

# ==================================================
# FIREWALL (UFW)
# ==================================================
log "Installing & configuring UFW"

apt-get update
apt-get install -y ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# --- Essential ---
ufw allow ${SSH_PORT}/tcp    comment 'SSH'
ufw allow 80/tcp             comment 'HTTP'
ufw allow 443/tcp            comment 'HTTPS'

# --- Panels / Admin (intentional) ---
ufw allow 8080/tcp           comment 'Web Admin'
ufw allow 8888/tcp           comment 'Nginx/OLS Admin'
ufw allow 2222/tcp           comment 'Control Panel'

ufw --force enable
log "UFW enabled"

# ==================================================
# FAIL2BAN
# ==================================================
log "Installing & configuring Fail2Ban"

apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
backend  = systemd
usedns   = warn
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = ${SSH_PORT}
EOF

systemctl enable --now fail2ban
log "Fail2Ban active"

# ==================================================
# KERNEL HARDENING (sysctl)
# ==================================================
log "Applying kernel hardening"

cat > /etc/sysctl.d/99-hardening.conf <<EOF
# IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096

# Ignore broadcast pings
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log martian packets
net.ipv4.conf.all.log_martians = 1

# Source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# TCP tuning
net.ipv4.tcp_fin_timeout = 15
EOF

sysctl --system
log "Kernel hardening applied"

# ==================================================
# CLEANUP
# ==================================================
log "Cleaning system"
apt-get autoremove -y
apt-get autoclean -y
unset SSH_PORT DEBIAN_FRONTEND

# ==================================================
# FINAL REPORT
# ==================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ Firewall : UFW enabled\e[0m"
echo -e "\e[1;32m ✔ Protection : Fail2Ban active\e[0m"
echo -e "\e[1;32m ✔ Kernel : Hardened\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo