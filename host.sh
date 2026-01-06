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
LOG="/var/log/server-hosting.log"
if touch "$LOG" &>/dev/null; then
  exec > >(tee -a "$LOG") 2>&1
  echo "[*] Logging enabled: $LOG"
fi

echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Hosting Script Started\e[0m"
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
# OS validation
# --------------------------------------------------
if ! grep -Eqi '^(ID=(ubuntu|debian)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "ERROR: Debian/Ubuntu only."
  exit 1
fi

# ==================================================
# GLOBAL CONFIG (STATIC)
# ==================================================
TIMEZONE="UTC"
SSH_PORT=22
OLS_ADMIN_PORT=7080
NETDATA_PORT=19999

DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="8.8.8.8"
DNS_TERTIARY="9.9.9.9"

export DEBIAN_FRONTEND=noninteractive

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

log "Updating system"
apt update && apt -y upgrade

apt install -y \
  curl wget unzip git sudo \
  ca-certificates gnupg lsb-release \
  ufw fail2ban software-properties-common \
  htop ncdu rsyslog dnsutils

# ==================================================
# DNS RESOLVER CONFIG (SERVER SIDE)
# ==================================================
log "Configuring system DNS resolver"

if systemctl list-unit-files | grep -q systemd-resolved; then
  cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=${DNS_PRIMARY} ${DNS_SECONDARY}
FallbackDNS=${DNS_TERTIARY}
EOF
  systemctl restart systemd-resolved
else
  chattr -i /etc/resolv.conf 2>/dev/null || true
  cat > /etc/resolv.conf <<EOF
nameserver ${DNS_PRIMARY}
nameserver ${DNS_SECONDARY}
nameserver ${DNS_TERTIARY}
options edns0 trust-ad
EOF
  chattr +i /etc/resolv.conf
fi

# ==================================================
# DNS A RECORD VERIFICATION
# ==================================================
log "Checking DNS A record for $FQDN"

SERVER_IP=$(curl -s https://api.ipify.org)
DNS_IP=$(dig +short "$FQDN" A | tail -n1)

if [[ "$SERVER_IP" != "$DNS_IP" ]]; then
  warn "DNS A record is NOT correct"
  echo " Expected IP : $SERVER_IP"
  echo " DNS IP      : ${DNS_IP:-NOT FOUND}"
  echo
  echo "👉 Please set this DNS record:"
  echo "   $FQDN  -->  $SERVER_IP"
  die "Fix DNS first, then re-run the script"
fi

log "DNS A record is valid"

# ==================================================
# FIREWALL
# ==================================================
log "Configuring UFW firewall"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow ${SSH_PORT}/tcp        # SSH
ufw allow 80/tcp                 # HTTP
ufw allow 443/tcp                # HTTPS
ufw allow ${OLS_ADMIN_PORT}/tcp  # OpenLiteSpeed Admin
ufw allow ${NETDATA_PORT}/tcp    # Netdata (restrict in production if needed)

ufw --force enable

# ==================================================
# FAIL2BAN
# ==================================================
log "Configuring Fail2Ban"

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 4

[sshd]
enabled = true
port = ${SSH_PORT}
EOF

systemctl enable --now fail2ban

# ==================================================
# KERNEL HARDENING
# ==================================================
log "Applying kernel hardening"

cat > /etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_fin_timeout = 15
net.core.somaxconn = 4096
EOF

sysctl --system

# ==================================================
# OPENLITESPEED + PHP
# ==================================================
log "Installing OpenLiteSpeed"

wget -qO- https://repo.litespeed.sh | bash
apt install -y openlitespeed \
  lsphp82 lsphp82-common lsphp82-curl \
  lsphp82-intl lsphp82-mysql lsphp82-opcache

systemctl enable lsws

# ==================================================
# SSL (LETSENCRYPT)
# ==================================================
log "Installing Certbot"
apt install -y certbot

log "Issuing SSL certificate for $FQDN"
systemctl stop lsws || true

certbot certonly \
  --standalone \
  --preferred-challenges http \
  --agree-tos \
  --non-interactive \
  -m "$ADMIN_EMAIL" \
  -d "$FQDN"

systemctl start lsws

log "SSL certificate issued successfully"

# ==================================================
# WP-CLI (for next scripts)
# ==================================================
log "Installing WP-CLI"
curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# ==================================================
# MONITORING
# ==================================================
log "Installing Netdata"
apt install -y netdata
systemctl enable netdata
systemctl start netdata

# ==================================================
# CLEANUP
# ==================================================
log "Cleaning system"
apt autoremove -y
apt autoclean -y

# ==================================================
# FINAL REPORT
# ==================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ Hostname : $FQDN\e[0m"
echo -e "\e[1;32m ✔ DNS      : OK\e[0m"
echo -e "\e[1;32m ✔ SSL      : Issued\e[0m"
echo -e "\e[1;32m ✔ Web      : OpenLiteSpeed\e[0m"
echo -e "\e[1;32m ✔ Firewall : UFW + Fail2Ban\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo

# ==================================================
# CLEAN EXIT
# ==================================================
unset TIMEZONE SSH_PORT OLS_ADMIN_PORT NETDATA_PORT
unset DNS_PRIMARY DNS_SECONDARY DNS_TERTIARY
unset HOSTNAME DOMAIN FQDN ADMIN_EMAIL
unset SERVER_IP DNS_IP DEBIAN_FRONTEND