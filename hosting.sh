#!/usr/bin/env bash
set -e

### ================================
### CONFIG (EDIT THESE)
### ================================
HOSTNAME="vps"
DOMAIN="example.com"
FQDN="${HOSTNAME}.${DOMAIN}"
ADMIN_EMAIL="admin@example.com"
TIMEZONE="UTC"
SSH_PORT=22
OLS_ADMIN_PORT=7080
### ================================

export DEBIAN_FRONTEND=noninteractive

log() {
  echo -e "\e[32m[✔] $1\e[0m"
}

warn() {
  echo -e "\e[33m[!] $1\e[0m"
}

### ================================
### BASIC SYSTEM SETUP
### ================================
log "Setting hostname & FQDN"
hostnamectl set-hostname "$FQDN"

echo "127.0.1.1 $FQDN $HOSTNAME" >> /etc/hosts

timedatectl set-timezone "$TIMEZONE"

log "Updating system"
apt update && apt -y upgrade

apt install -y \
  curl wget unzip git sudo \
  ca-certificates gnupg lsb-release \
  ufw fail2ban software-properties-common \
  htop ncdu rsyslog

### ================================
### DNS RESOLVER SANITY
### ================================
log "Configuring resolv.conf"
cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9
EOF

systemctl restart systemd-resolved

### ================================
### FIREWALL (UFW)
### ================================
log "Configuring UFW"
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow ${OLS_ADMIN_PORT}/tcp
ufw --force enable

### ================================
### FAIL2BAN
### ================================
log "Configuring Fail2Ban"
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 4
bantime = 1h

[litespeed]
enabled = true
port = http,https
filter = litespeed
logpath = /usr/local/lsws/logs/error.log
maxretry = 6
bantime = 1h
EOF

systemctl enable --now fail2ban

### ================================
### ANTI-DDOS / KERNEL HARDENING
### ================================
log "Applying sysctl hardening"
cat >> /etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15
net.core.somaxconn = 4096
EOF

sysctl --system

### ================================
### OPENLITESPEED
### ================================
log "Installing OpenLiteSpeed"
wget -O - https://repo.litespeed.sh | bash
apt install -y openlitespeed lsphp82 lsphp82-common lsphp82-curl \
  lsphp82-intl lsphp82-mysql lsphp82-opcache lsphp82-zip

systemctl enable lsws

### ================================
### CERTBOT (LETSENCRYPT)
### ================================
log "Installing Certbot"
apt install -y certbot

warn "⚠ SSL will work only if DNS A record is correct"

### ================================
### WP-CLI
### ================================
log "Installing WP-CLI"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

### ================================
### WORDPRESS HARDENING TEMPLATE
### ================================
log "Preparing WP hardening snippets"
cat > /root/wp-hardening.txt <<EOF
disable_file_edit
disable_xmlrpc
limit_login_attempts
force_ssl_admin
security_headers
EOF

### ================================
### SERVER MONITORING (NETDATA)
### ================================
log "Installing Netdata"
curl -s https://get.netdata.cloud | bash -s -- --disable-telemetry

### ================================
### CLEANUP
### ================================
log "Cleaning up"
apt autoremove -y
apt autoclean -y

### ================================
### FINAL REPORT
### ================================
echo
echo -e "\e[36m══════════════════════════════════════════════\e[0m"
echo -e " \e[32m✔ Hosting server bootstrap completed\e[0m"
echo -e " \e[32m✔ Hostname : $FQDN\e[0m"
echo -e " \e[32m✔ Web      : OpenLiteSpeed\e[0m"
echo -e " \e[32m✔ Firewall: UFW + Fail2Ban\e[0m"
echo -e " \e[32m✔ Monitor : Netdata\e[0m"
echo -e "\e[36m══════════════════════════════════════════════\e[0m"