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
fi

# --------------------------------------------------
# Root Check
# --------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

# --------------------------------------------------
# OS Check
# --------------------------------------------------
if ! grep -Eqi '^(ID=(ubuntu|debian)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "ERROR: Debian/Ubuntu only."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------
# GLOBAL CONFIG
# --------------------------------------------------
TIMEZONE="UTC"

# Global DNS
DNS_MAIN1="1.1.1.1"
DNS_MAIN2="1.0.0.1"
DNS_MAIN3="9.9.9.9"
DNS_MAIN4="149.112.112.112"
DNS_MAIN5="8.8.8.8"
DNS_MAIN6="4.2.2.4"

# Iranian / Bypass DNS (Fallback)
DNS_LOCAL1="185.51.200.2"
DNS_LOCAL2="178.22.122.100"
DNS_LOCAL3="10.202.10.102"
DNS_LOCAL4="10.202.10.202"
DNS_LOCAL5="185.55.225.25"
DNS_LOCAL6="185.55.225.26"
DNS_LOCAL7="181.41.194.177"
DNS_LOCAL8="181.41.194.186"

# --------------------------------------------------
# INPUT
# --------------------------------------------------
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
# DNS CONFIG (SAFE MODE)
# --------------------------------------------------
log "Configuring DNS (systemd-resolved)"

cat >> /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=${DNS_MAIN1} ${DNS_MAIN3} ${DNS_MAIN5} ${DNS_LOCAL1} ${DNS_LOCAL3} ${DNS_LOCAL5} ${DNS_LOCAL7}
FallbackDNS=${DNS_MAIN2} ${DNS_MAIN4} ${DNS_MAIN6} ${DNS_LOCAL2} ${DNS_LOCAL4} ${DNS_LOCAL6} ${DNS_LOCAL8}
DNSOverTLS=opportunistic
DNSSEC=no
Cache=yes
EOF

cat >> /etc/resolv.conf <<EOF
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

  systemctl enable systemd-resolved
  systemctl start systemd-resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  systemctl restart systemd-resolved

fi

log "DNS configured successfully"
resolvectl status

# --------------------------------------------------
# DNS A RECORD CHECK
# --------------------------------------------------
log "Validating DNS A record"

SERVER_IP=$(curl -fsSL https://api.ipify.org || true)
DNS_IP=$(dig +short "$FQDN" A | head -n1 || true)

if [[ -n "$SERVER_IP" && "$SERVER_IP" != "$DNS_IP" ]]; then
  warn "A record mismatch"
  echo "Server IP: $SERVER_IP"
  echo "DNS IP   : ${DNS_IP:-NOT FOUND}"
  die "Fix DNS first"
fi

log "DNS record OK"

# --------------------------------------------------
# SSL (Certbot)
# --------------------------------------------------
log "Installing Certbot"
apt-get install -y certbot

log "Issuing SSL certificate"
certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  -m "$ADMIN_EMAIL" \
  -d "$FQDN"

log "SSL ready"

# --------------------------------------------------
# NETWORK MONITOR (LOW RESOURCE)
# --------------------------------------------------
log "Installing vnStat"
apt-get install -y vnstat

systemctl enable vnstat
systemctl start vnstat

# --------------------------------------------------
# CLEANUP
# --------------------------------------------------
log "Cleanup"
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
