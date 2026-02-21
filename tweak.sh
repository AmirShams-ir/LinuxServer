#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# CloudPanel CloudPanel Harden And Optimizer
# Supports: Debian 12/13, Ubuntu 22.04/24.04
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# License: See GitHub repository for license details.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ========================= Root =========================
if [[ $EUID -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi

info(){ printf "\e[34m%s\e[0m\n" "$*"; }
ok(){   printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn(){ printf "\e[33m[!] %s\e[0m\n" "$*"; }
die(){  printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }
has_systemd(){ [[ -d /run/systemd/system ]]; }

export DEBIAN_FRONTEND=noninteractive

# ========================= OS Validation =========================
source /etc/os-release || die "Cannot detect OS"
case "$ID" in
  debian) [[ "$VERSION_ID" == "12" || "$VERSION_ID" == "13" ]] || die "Unsupported Debian";;
  ubuntu) [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]] || die "Unsupported Ubuntu";;
  *) die "Unsupported OS";;
esac
ok "OS: $PRETTY_NAME"

# ========================= Logging =========================
LOG="/var/log/cloudpanel-enterprise-v4.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"
exec > >(tee -a "$LOG") 2> >(tee -a "$LOG" >&2)

info "═══════════════════════════════════════════"
info "✔ CloudPanel Harden And Optimizer"
info "═══════════════════════════════════════════"

# ========================= Kernel Tuning =========================
info "Applying kernel tuning..."
SYSCTL="/etc/sysctl.d/99-ultra-hosting.conf"
RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
CONNTRACK=262144; [[ "$RAM_MB" -lt 1500 ]] && CONNTRACK=131072
modprobe nf_conntrack 2>/dev/null || true
modprobe tcp_bbr 2>/dev/null || true

cat > "$SYSCTL" <<EOF
fs.file-max=500000
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_default=262144
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.ip_local_port_range=1024 65000
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.rp_filter=1
EOF

if [[ -d /proc/sys/net/netfilter ]]; then
  sysctl -w net.netfilter.nf_conntrack_max=$CONNTRACK 2>/dev/null || true
fi

sysctl --system >/dev/null

ok "Kernel tuned"

# ================= Remove Old PHP Versions =================

info "Stopping old PHP-FPM services..."

for v in 7.1 7.2 7.3 7.4 8.0 8.1 8.2; do
    systemctl stop php$v-fpm 2>/dev/null || true
    systemctl disable php$v-fpm 2>/dev/null || true
done

systemctl daemon-reload

info "Restarting services..."
systemctl restart php8.3-fpm
systemctl restart nginx
systemctl restart mariadb

ok "Old PHP Stop Done. Remaining PHP services:"
systemctl list-units --type=service | grep php

# ================= Disable Varnish =========================
systemctl disable varnish 2>/dev/null || true
systemctl stop varnish 2>/dev/null || true
ok "Varnish disabled"

# ================= Redis Optimize =======================+==
if [ -f /etc/redis/redis.conf ]; then
  sed -i "s/^maxmemory .*/maxmemory 128mb/" /etc/redis/redis.conf || true
  grep -q "^maxmemory " /etc/redis/redis.conf || echo "maxmemory 128mb" >> /etc/redis/redis.conf
  echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
  systemctl restart redis || true
fi

ok "Redis optimized"

# ========================= MariaDB Adaptive =========================
RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
BP=$((RAM_MB/4))
[[ $BP -lt 256 ]] && BP=256
cat > /etc/mysql/mariadb.conf.d/99-ultra.cnf <<EOF
[mysqld]
innodb_buffer_pool_size=${BP}M
innodb_log_file_size=64M
max_connections=20
tmp_table_size=32M
max_heap_table_size=32M
query_cache_type=0
query_cache_size=0
EOF

systemctl restart mariadb

ok "MariaDB optimized"

# ========================= PHP-FPM Adaptive =========================
for DIR in /etc/php/*/fpm/pool.d; do
  [ -d "$DIR" ] || continue
  for FILE in $DIR/*.conf; do
    sed -i "s/^pm = .*/pm = ondemand/" "$FILE" || true
    sed -i "s/^pm.max_children.*/pm.max_children = 2/" "$FILE" || true
    sed -i "s/^pm.process_idle_timeout.*/pm.process_idle_timeout = 10s/" "$FILE" || true
    sed -i "s/^pm.max_requests.*/pm.max_requests = 300/" "$FILE" || true
  done
done
systemctl restart php*-fpm 2>/dev/null || true

ok "PHP-FPM ultra optimized"

# ================= OPcache Tune =================
for INI in /etc/php/*/fpm/php.ini; do
  sed -i "s/^memory_limit = .*/memory_limit = 256M/" "$INI" || true
  sed -i "s/^max_execution_time = .*/max_execution_time = 60/" "$INI" || true
  sed -i "s/^max_input_vars = .*/max_input_vars = 5000/" "$INI" || true
  sed -i "s/^opcache.memory_consumption=.*/opcache.memory_consumption=128/" "$INI" || true
  sed -i "s/^opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=16/" "$INI" || true
  sed -i "s/^opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/" "$INI" || true
done
systemctl restart php*-fpm 2>/dev/null || true
ok "PHP limits tuned"

# ========================= Firewall =========================
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 8443
ufw --force enable
ok "Firewall enabled"

# ========================= Fail2Ban =========================
info "Installing and configuring Fail2Ban..."

apt-get update -y || die "APT update failed"
apt-get install -y fail2ban apache2-utils || die "Fail2Ban installation failed"

mkdir -p /etc/fail2ban

cat > /etc/fail2ban/jail.local <<'EOF'
# Default Settings
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd
usedns   = warn
banaction = iptables-multiport

# SSH Protection
[sshd]
enabled  = true
port     = 22
logpath  = /var/log/auth.log
maxretry = 5

# CloudPanel Nginx Protection
[nginx-badbots]
enabled  = true
port     = http,https
logpath  = /home/*/logs/nginx/*access.log
maxretry = 5

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /home/*/logs/nginx/*error.log
maxretry = 5
EOF

systemctl enable fail2ban
systemctl restart fail2ban || die "Fail2Ban failed to start"
sleep 2
fail2ban-client status
ok "Fail2Ban fully hardened and active"

# ========================= Final =========================
info "═══════════════════════════════════════════"
ok    "CloudPanel Harden and Optimized"
ok    "Full Security Applied"
warn  "Reboot recommended"
info "═══════════════════════════════════════════"
