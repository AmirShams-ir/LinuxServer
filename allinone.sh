#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Net Application Bootstrap (Nginx + PHP + MariaDB + SSL)
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# License: See GitHub repository for license details.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Root Handling
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$0" "$@"
  else
    printf "Root privileges required.\n"
    exit 1
  fi
fi

# ==============================================================================
# OS Validation
# ==============================================================================
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
else
  printf "Cannot detect OS.\n"
  exit 1
fi

[[ "${ID}" == "debian" || "${ID}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* ]] \
  || { printf "Debian/Ubuntu only.\n"; exit 1; }

CODENAME="${VERSION_CODENAME:-$(lsb_release -sc 2>/dev/null || true)}"

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
# Helpers
# ==============================================================================
info() { printf "\e[34m%s\e[0m\n" "$*"; }
rept() { printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn() { printf "\e[33m[!] %s\e[0m\n" "$*"; }
die()  { printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Cloud Panel Install and Configure Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# User Input
# ==============================================================================
info "Collecting configuration input..."

read -rp "Enter domain (example.com): " DOMAIN
[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Invalid domain"

WEBROOT="/var/www/$DOMAIN"

info "Detecting server public IP..."

# Try multiple reliable services
PUBLIC_IP=$(curl -4 -s --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || true)
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || true)
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(hostname -I | awk '{print $1}')

[[ -z "$PUBLIC_IP" ]] && die "Could not detect public IP"

info "Detected IP: $PUBLIC_IP"

# Hostname setup
HOSTNAME_SHORT="host"
FQDN="${HOSTNAME_SHORT}.${DOMAIN}"

info "Setting FQDN to $FQDN"

hostnamectl set-hostname "$FQDN" || die "Failed to set hostname"

# Update /etc/hosts safely
if ! grep -q "$FQDN" /etc/hosts; then
    sed -i "/127.0.1.1/d" /etc/hosts
    echo "$PUBLIC_IP    $FQDN $HOSTNAME_SHORT" >> /etc/hosts
fi

# DNS check (optional warning only)
RESOLVED_IP=$(getent hosts "$FQDN" | awk '{print $1}' | head -n1)

if [[ "$RESOLVED_IP" != "$PUBLIC_IP" ]]; then
    warn "Warning: DNS for $FQDN does not resolve to this server IP"
else
    info "DNS resolution looks correct"
fi

rept "FQDN successfully configured"

# ==============================================================================
# Timezone & Locale
# ==============================================================================
info "Starting timezone and locale configuration..."

if has_systemd; then
  CURRENT_TZ="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  [[ "$CURRENT_TZ" != "UTC" ]] && timedatectl set-timezone UTC
else
  warn "Systemd not detected, timezone enforcement skipped"
fi

LOCALE="en_US.UTF-8"
if ! locale -a | grep -qx "$LOCALE"; then
  sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen "$LOCALE"
fi

update-locale LANG="$LOCALE" LC_ALL="$LOCALE"
export LANG="$LOCALE" LC_ALL="$LOCALE"

timedatectl set-timezone UTC
timedatectl set-ntp true

rept "Timezone and locale configuration completed"

# ==============================================================================
# Base System Packages
# ==============================================================================
info "Installing base packages..."

# Update system
apt update -y || die "apt update failed"
apt upgrade -y || die "apt upgrade failed"

# Install required base packages
apt install -y \
    curl \
    wget \
    gnupg \
    ca-certificates \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release \
    git \
    zip \
    unzip \
    tar \
    sudo \
    nano \
    vim \
    htop \
    net-tools \
    dnsutils \
    jq \
    ufw \
    fail2ban \
    cron \
    rsync \
    zip \
    logrotate \
    build-essential \
    bash-completion \
    unattended-upgrades || die "Base package installation failed"

rept "Base packages installed"

# ------------------------------------------------------------------------------
# Disable conflicting services (if any)
# ------------------------------------------------------------------------------
for PORT in 80 443 8443 3306; do
    if ss -lntp | grep -q ":$PORT "; then
        warn "Port $PORT already in use. CloudPanel install may fail."
    fi
done

# ------------------------------------------------------------------------------
# Basic sysctl tuning
# ------------------------------------------------------------------------------
cat >> /etc/sysctl.conf <<EOF

# Cloud Hosting Optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
vm.swappiness = 10
EOF

sysctl -p

# ==============================================================================
# Swap Configuration
# ==============================================================================
info "Starting swap configuration..."

if ! swapon --show | grep -q swap; then
  RAM_MB="$(free -m | awk '/Mem:/ {print $2}')"
  [[ "$RAM_MB" -lt 2048 ]] && SWAP_SIZE="2G" || SWAP_SIZE="1G"

  fallocate -l "$SWAP_SIZE" /swapfile || die "Swap allocation failed"
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab

  rept "Swap created and enabled"
else
  warn "Swap already active"
fi

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

sysctl --system >/dev/null || die "Sysctl reload failed"

rept "Sysctl baseline applied"

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
  rept "TCP BBR enabled"
else
  warn "BBR not supported on this kernel"
fi

# ==============================================================================
# Journald Limits
# ==============================================================================
info "Configuring journald limits..."

if has_systemd; then
  mkdir -p /etc/systemd/journald.conf.d
  cat <<EOF >/etc/systemd/journald.conf.d/limit.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
EOF
  systemctl restart systemd-journald
  rept "Journald limits applied"
else
  warn "Systemd not detected, journald skipped"
fi

# ==============================================================================
# Cleanup
# ==============================================================================
info "Performing cleanup..."

apt-get autoremove -y
apt-get autoclean -y

unset LOG CURRENT_TZ LOCALE RAM_MB SWAP_SIZE

rept "Cleanup completed"

# ==============================================================================
# Install CloudPanel
# ==============================================================================
install_cloudpanel() {

  if systemctl list-units --full -all | grep -q clp-agent; then
    warn "CloudPanel already installed. Skipping."
    return
  fi

  info "Installing CloudPanel..."
  curl -fsSL https://installer.cloudpanel.io/ce/v2/install.sh -o /tmp/clp.sh \
    || die "Download failed"

  bash /tmp/clp.sh || die "CloudPanel install failed"
  rm -f /tmp/clp.sh

  sleep 5

  systemctl is-active --quiet clp-agent \
    && info "CloudPanel service running" \
    || die "CloudPanel service failed"
}

# ==============================================================================
# Optimize MariaDB for 1GB
# ==============================================================================
optimize_mariadb_1gb() {

  info "Optimizing MariaDB for 1GB..."

  CONF="/etc/mysql/mariadb.conf.d/99-1gb.cnf"

  cat > "$CONF" <<EOF
[mysqld]
innodb_buffer_pool_size=256M
innodb_log_file_size=64M
innodb_flush_method=O_DIRECT
max_connections=30
tmp_table_size=32M
max_heap_table_size=32M
thread_cache_size=8
table_open_cache=400
query_cache_type=0
query_cache_size=0
EOF

  systemctl restart mariadb
  info "MariaDB optimized."
}

# ==============================================================================
# Optimize PHP-FPM for 1GB
# ==============================================================================
optimize_phpfpm_1gb() {

  info "Optimizing PHP-FPM pools..."

  for ver in 8.1 8.2; do
    POOL_DIR="/etc/php/$ver/fpm/pool.d"
    [[ -d "$POOL_DIR" ]] || continue

    for pool in "$POOL_DIR"/*.conf; do
      sed -i "s/^pm.max_children.*/pm.max_children = 4/" "$pool" || true
      sed -i "s/^pm.start_servers.*/pm.start_servers = 2/" "$pool" || true
      sed -i "s/^pm.min_spare_servers.*/pm.min_spare_servers = 1/" "$pool" || true
      sed -i "s/^pm.max_spare_servers.*/pm.max_spare_servers = 2/" "$pool" || true
      sed -i "s/^pm.max_requests.*/pm.max_requests = 300/" "$pool" || true
    done

    systemctl restart php$ver-fpm
  done

  info "PHP-FPM optimized."
}

# ==============================================================================
# Enable & Optimize OPcache
# ==============================================================================
optimize_opcache() {

  info "Configuring OPcache..."

  for ver in 8.1 8.2; do
    OPCACHE_FILE="/etc/php/$ver/fpm/conf.d/99-opcache.ini"
    [[ -d "/etc/php/$ver" ]] || continue

    cat > "$OPCACHE_FILE" <<EOF
opcache.enable=1
opcache.memory_consumption=64
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.validate_timestamps=1
opcache.revalidate_freq=60
opcache.save_comments=1
EOF

    systemctl restart php$ver-fpm
  done

  info "OPcache configured."
}

# ==============================================================================
# Disable Redis (if exists)
# ==============================================================================
disable_redis() {

  if systemctl list-unit-files | grep -q redis; then
    warn "Disabling Redis (not required for this setup)..."
    systemctl stop redis-server || true
    systemctl disable redis-server || true
  fi
}

# ==============================================================================
# Execute
# ==============================================================================
install_cloudpanel
optimize_mariadb_1gb
optimize_phpfpm_1gb
optimize_opcache
disable_redis
final_message

# ==============================================================================
# Cleanup
# ==============================================================================

cleanup() {

  info "Running cleanup tasks..."

  # Remove temporary installer files
  rm -f /tmp/clp.sh 2>/dev/null || true

  # Clear apt cache safely
  apt autoremove -y >/dev/null 2>&1 || true
  apt autoclean -y >/dev/null 2>&1 || true

  # Clear journal logs older than 7 days (prevent log bloat on 1GB VPS)
  journalctl --vacuum-time=7d >/dev/null 2>&1 || true

  # Clear temporary directories
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

  # Reload systemd daemon (safe refresh)
  systemctl daemon-reload || true

  info "Cleanup completed."
}

# ==============================================================================
# Firewall (UFW)
# ==============================================================================
info "Installing and configuring UFW..."

apt-get update || die "APT update failed"
apt-get install -y ufw || die "UFW installation failed"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 8443/tcp comment 'CLOUDPANEL'

ufw --force enable

rept "Firewall installed and configured and enabled"

# ==============================================================================
# Fail2Ban
# ==============================================================================
info "Installing and configuring Fail2Ban..."

apt-get update -y
apt-get install -y fail2ban apache2-utils || die "Fail2Ban installation failed"

mkdir -p /etc/fail2ban/filter.d

# ------------------------------------------------------------------------------
# phpMyAdmin filter
# ------------------------------------------------------------------------------
cat > /etc/fail2ban/filter.d/phpmyadmin.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(POST).*/index\.php.*" (200|302)
ignoreregex =
EOF

# ------------------------------------------------------------------------------
# Jail Configuration
# ------------------------------------------------------------------------------
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
backend  = systemd
usedns   = warn
banaction = iptables-multiport
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

# ----------------------
# SSH Protection
# ----------------------
[sshd]
enabled = true
port    = 22
logpath = /var/log/auth.log

# ----------------------
# Nginx Basic Auth
# ----------------------
[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 5

# ----------------------
# phpMyAdmin Login Protection
# ----------------------
[phpmyadmin]
enabled  = true
port     = http,https
filter   = phpmyadmin
logpath  = /var/log/nginx/access.log
maxretry = 5
EOF

systemctl enable fail2ban
systemctl restart fail2ban || die "Fail2Ban failed to start"

sleep 2
fail2ban-client status

rept "Fail2Ban fully hardened and active"

# ==============================================================================
# Kernel Hardening
# ==============================================================================
info "Applying kernel hardening..."

cat > /etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_fin_timeout = 15
EOF

sysctl --system >/dev/null || die "Sysctl reload failed"

rept "Kernel hardening applied"

# ==============================================================================
# Cleanup
# ==============================================================================
info "Performing cleanup..."

apt-get autoremove -y
apt-get autoclean -y

unset SSH_PORT

rept "Cleanup completed"

# ==============================================================================
# Security Summary
# ==============================================================================
info "══════════════════════════════════════════════"
rept "Firewall  : UFW enabled"
rept "Protection: Fail2Ban active"
rept "Kernel    : Hardened"
info "══════════════════════════════════════════════"

# ==============================================================================
# Final Info
# ==============================================================================
final_message() {

  IP=$(hostname -I | awk '{print $1}')

  info "====================================================="
  rept " CloudPanel Installed & Optimized for 1GB VPS"
  rept " Access: https://$IP:8443"
  rept " MariaDB tuned"
  rept " PHP-FPM limited"
  rept " OPcache enabled"
  rept " Redis disabled"
  info "====================================================="
}
