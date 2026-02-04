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
LOG="/var/log/server-network.log"
if touch "$LOG" &>/dev/null; then
  exec > >(tee -a "$LOG") 2>&1
  echo "[*] Logging enabled: $LOG"
fi

echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Network Setup Script Started\e[0m"
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
# GLOBAL CONFIG
# ==================================================
TIMEZONE="UTC"

DNS_MAIN1="1.1.1.1"
DNS_MAIN2="1.0.0.1"
DNS_MAIN3="8.8.8.8"
DNS_MAIN4="4.2.2.4"
DNS_MAIN5="9.9.9.9"
DNS_MAIN6="149.112.112.112"

DNS_LOCAL1="185.51.200.2"
DNS_LOCAL2="178.22.122.100"
DNS_LOCAL3="10.202.10.102"
DNS_LOCAL4="10.202.10.202"
DNS_LOCAL5="185.55.225.25"
DNS_LOCAL6="185.55.225.26"
DNS_LOCAL7="181.41.194.177"
DNS_LOCAL8="181.41.194.186"

# ==================================================
# INTERACTIVE CONFIG
# ==================================================
read -rp "Enter hostname (e.g. vps): " HOSTNAME
read -rp "Enter domain name (e.g. example.com): " DOMAIN
read -rp "Enter admin email (SSL & alerts): " ADMIN_EMAIL

[[ -z "$HOSTNAME" || -z "$DOMAIN" || -z "$ADMIN_EMAIL" ]] && {
  echo "ERROR: Hostname, domain and email must not be empty."
  exit 1
}

FQDN="${HOSTNAME}.${DOMAIN}"

# ==================================================
# HELPERS
# ==================================================
log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ==================================================
# BASIC SYSTEM
# ==================================================
log "Setting hostname & FQDN"
hostnamectl set-hostname "$FQDN" || true
grep -q "$FQDN" /etc/hosts || echo "127.0.1.1 $FQDN $HOSTNAME" >> /etc/hosts

log "Setting timezone"
timedatectl set-timezone "$TIMEZONE" || true

log "Updating system packages"
apt-get update
apt-get -y dist-upgrade

log "Installing base utilities"
apt-get install -y \
  curl wget unzip git sudo \
  ca-certificates gnupg lsb-release \
  htop ncdu rsyslog dnsutils

# ==================================================
# DNS RESOLVER CONFIG
# ==================================================
log "Configuring system DNS resolver"

if systemctl list-unit-files | grep -q systemd-resolved; then
  sed -i '/^\[Resolve\]/,$d' /etc/systemd/resolved.conf 2>/dev/null || true
  cat >> /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=${DNS_MAIN1} ${DNS_MAIN3} ${DNS_MAIN5} ${DNS_LOCAL1} ${DNS_LOCAL3} ${DNS_LOCAL5} ${DNS_LOCAL7}
FallbackDNS=${DNS_MAIN2} ${DNS_MAIN4} ${DNS_MAIN6} ${DNS_LOCAL2} ${DNS_LOCAL4} ${DNS_LOCAL6} ${DNS_LOCAL8}
DNSSEC=no
EOF
  systemctl restart systemd-resolved
else
  cat > /etc/resolv.conf <<EOF
nameserver ${DNS_MAIN1}
nameserver ${DNS_MAIN2}
nameserver ${DNS_MAIN3}
nameserver ${DNS_MAIN4}
nameserver ${DNS_MAIN5}
nameserver ${DNS_MAIN6}

nameserver ${DNS_LOCAL1}
nameserver ${DNS_LOCAL2}
nameserver ${DNS_LOCAL3}
nameserver ${DNS_LOCAL4}
nameserver ${DNS_LOCAL5}
nameserver ${DNS_LOCAL6}
nameserver ${DNS_LOCAL7}
nameserver ${DNS_LOCAL8}

options edns0
EOF
fi

log "DNS resolver configured"

# ==================================================
# DNS A RECORD VERIFICATION
# ==================================================
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

log "DNS A record verified successfully"

# ==================================================
# SSL (LETSENCRYPT)
# ==================================================
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

log "SSL certificate issued successfully"

# ==================================================
# LIGHTWEIGHT NETWORK MONITORING
# ==================================================
log "Installing lightweight network monitoring (vnStat)"
apt-get install -y vnstat

systemctl enable vnstat
systemctl start vnstat

log "vnStat enabled (low resource usage)"

# ==================================================
# CLEANUP
# ==================================================
log "Cleaning system"
apt-get autoremove -y
apt-get autoclean -y

# ==================================================
# FINAL REPORT
# ==================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ Hostname : $FQDN\e[0m"
echo -e "\e[1;32m ✔ DNS      : OK\e[0m"
echo -e "\e[1;32m ✔ SSL      : Issued\e[0m"
echo -e "\e[1;32m ✔ Monitor  : vnStat\e[0m"
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
