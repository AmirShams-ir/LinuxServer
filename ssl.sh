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

set -Eeuo pipefail

# ==============================================================================
# Root / sudo handling
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "🔐 Root privileges required. Please enter sudo password..."
    exec sudo -E bash "$0" "$@"
  else
    echo "❌ ERROR: This script must be run as root."
    exit 1
  fi
fi

# ==============================================================================
# OS validation
# ==============================================================================
if [[ ! -f /etc/os-release ]] || \
   ! grep -Eqi '^(ID=(debian|ubuntu)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "❌ ERROR: Unsupported OS. Debian/Ubuntu only."
  exit 1
fi

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/server-ssl.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "[✔] Logging enabled: $LOG"

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ TLS/SSL Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# --------------------------------------------------
# INPUT
# --------------------------------------------------
TIMEZONE="UTC"
read -rp "Enter hostname (e.g. vps): " HOSTNAME 
read -rp "Enter domain name (e.g. example.com): " DOMAIN 
read -rp "Enter admin email (SSL & alerts): " ADMIN_EMAIL 
[[ -z "$HOSTNAME" || -z "$DOMAIN" || -z "$ADMIN_EMAIL" ]] && {
  echo "ERROR: Empty inputs"
  exit 1
}
FQDN="${HOSTNAME}.${DOMAIN}"
# --------------------------------------------------
# HELPERS
# --------------------------------------------------
log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# --------------------------------------------------
# BASIC SYSTEM
# --------------------------------------------------
log "Setting hostname"
hostnamectl set-hostname "$FQDN" || true
grep -q "$FQDN" /etc/hosts || echo "127.0.1.1 $FQDN $HOSTNAME" >> /etc/hosts

log "Setting timezone"
timedatectl set-timezone "$TIMEZONE" || true

log "Updating system"
apt-get update
apt-get -y dist-upgrade

log "Installing base packages"
apt-get install -y \
  curl wget git sudo unzip \
  ca-certificates gnupg lsb-release \
  htop ncdu dnsutils

# --------------------------------------------------
# DNS A RECORD CHECK
# --------------------------------------------------
log "Validating DNS A record for $FQDN"

SERVER_IP=$(curl -fsSL https://api.ipify.org)
DNS_IP=$(dig +short "$FQDN" A | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)

if [[ "$SERVER_IP" != "$DNS_IP" ]]; then
  warn "DNS A record mismatch"
  echo " Expected IP : $SERVER_IP"
  echo " DNS IP      : ${DNS_IP:-NOT FOUND}"
  echo
  echo "👉 Please set DNS A record:"
  echo "   $FQDN  →  $SERVER_IP"
  die "Fix DNS first, then re-run the script"
fi

log "✔ DNS A record verified successfully"

# --------------------------------------------------
# SSL (Certbot)
# --------------------------------------------------
log "Installing Certbot"
apt-get install -y certbot

if systemctl is-active --quiet lsws; then
  systemctl stop lsws
  NEED_LSWS_RESTART=1
fi

log "Issuing SSL certificate for $FQDN"
certbot certonly \
  --standalone \
  --preferred-challenges http \
  --agree-tos \
  --non-interactive \
  -m "$ADMIN_EMAIL" \
  -d "$FQDN"

[[ "${NEED_LSWS_RESTART:-0}" == "1" ]] && systemctl start lsws

log "✔ SSL certificate issued successfully"

# --------------------------------------------------
# NETWORK MONITOR (LOW RESOURCE)
# --------------------------------------------------
log "Installing vnStat"
apt-get install -y vnstat

systemctl enable vnstat
systemctl start vnstat

apt-get autoremove -y
apt-get autoclean -y

log "✔ Network Monitor Installed successfully"

# ==================================================
# FINAL REPORT
# ==================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ Hostname     : $FQDN\e[0m"
echo -e "\e[1;32m ✔ SSL/TLS      : Issued\e[0m"
echo -e "\e[1;32m ✔ Monitor      : vnStat\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo

# ==================================================
# CLEAN EXIT
# ==================================================
unset TIMEZONE
unset DNS_MAIN1 DNS_MAIN2 DNS_MAIN3 DNS_MAIN4 DNS_MAIN5 DNS_MAIN6
unset DNS_LOCAL1 DNS_LOCAL2 DNS_LOCAL3 DNS_LOCAL4 DNS_LOCAL5 DNS_LOCAL6 DNS_LOCAL7 DNS_LOCAL8
unset HOSTNAME DOMAIN FQDN ADMIN_EMAIL
unset SERVER_IP DNS_IP DEBIAN_FRONTEND
