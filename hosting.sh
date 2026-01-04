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
#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Mandatory base initialization for fresh Debian/Ubuntu VPS
# Author: BabyBoss
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# -----------------------------------------------------------------------------

set -e

# ==================================================
# CONFIGS
# ==================================================
TIMEZONE="UTC"
SSH_PORT=22
OLS_ADMIN_PORT=7080
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="8.8.8.8"
DNS_TERTIARY="9.9.9.9"

read -rp "Enter hostname (e.g. vps): " HOSTNAME
read -rp "Enter domain name (e.g. example.com): " DOMAIN
read -rp "Enter admin email (for SSL & alerts): " ADMIN_EMAIL

FQDN="${HOSTNAME}.${DOMAIN}"
# ==================================================

export DEBIAN_FRONTEND=noninteractive

log() {
  echo -e "\e[32m[✔] $1\e[0m"
}

warn() {
  echo -e "\e[33m[!] $1\e[0m"
}

# ==================================================
# BASIC SYSTEM
# ==================================================
log "Setting hostname & FQDN"
hostnamectl set-hostname "$FQDN" || true
grep -q "$FQDN" /etc/hosts || echo "127.0.1.1 $FQDN $HOSTNAME" >> /etc/hosts

log "Setting timezone"
timedatectl set-timezone "$TIMEZONE" || true

log "System update"
apt update && apt -y upgrade

apt install -y \
  curl wget unzip git sudo \
  ca-certificates gnupg lsb-release \
  ufw fail2ban software-properties-common \
  htop ncdu rsyslog \
  dnsutils

# ==================================================
# DNS CONFIG (AUTO-DETECT)
# ==================================================
log "Configuring DNS"

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
# FIREWALL (UFW)
# ==================================================
log "Configuring UFW"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow ${OLS_ADMIN_PORT}/tcp
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

[litespeed]
enabled = true
port = http,https
logpath = /usr/local/lsws/logs/error.log
maxretry = 6
EOF

systemctl enable --now fail2ban

# ==================================================
# ANTI-DDOS / KERNEL HARDENING
# ==================================================
log "Applying kernel hardening"
cat > /etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_max_syn_backlog = 4096
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
  lsphp82-intl lsphp82-mysql \
  lsphp82-opcache 

systemctl enable lsws

# ==================================================
# CERTBOT
# ==================================================
log "Installing Certbot"
apt install -y certbot
warn "SSL issuance requires correct DNS A record"

# ==================================================
# WP-CLI
# ==================================================
log "Installing WP-CLI"
curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# ==================================================
# WORDPRESS HARDENING TEMPLATE
# ==================================================
log "Creating WP hardening checklist"
cat > /root/wp-hardening.todo <<EOF
- Disable XML-RPC
- Disable file editing
- Force SSL admin
- Set correct file permissions
- Security headers
- Limit login attempts
EOF

# ==================================================
# SERVER MONITORING (NETDATA)
# ==================================================
log "Installing Netdata (Debian repo)"
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
echo -e "\e[36m══════════════════════════════════════════════\e[0m"
echo -e " \e[32m✔ Hosting bootstrap completed successfully\e[0m"
echo -e " \e[32m✔ Hostname : $FQDN\e[0m"
echo -e " \e[32m✔ Firewall : UFW + Fail2Ban\e[0m"
echo -e " \e[32m✔ Web      : OpenLiteSpeed\e[0m"
echo -e " \e[32m✔ Monitor  : Netdata\e[0m"
echo -e "\e[36m══════════════════════════════════════════════\e[0m"
echo
