#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# CloudPanel Enterprise Installer (Stable • Self-Healing • Production)
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
info "✔ CloudPanel Enterprise Installer v4"
info "═══════════════════════════════════════════"

# ========================= Self-Healing =========================
if dpkg --audit | grep -q .; then
  warn "Broken dpkg detected. Repairing..."
  apt install -f -y || true
  dpkg --configure -a || true
fi

# ========================= Time & NTP =========================
if has_systemd; then
  timedatectl set-timezone UTC || true
  timedatectl set-ntp true || true
fi

# ========================= FQDN =========================
info "Configuring FQDN..."
read -rp "Enter Subdomain (e.g. vps): " SUB
read -rp "Enter Domain (example.com): " DOMAIN
[[ "$SUB" =~ ^[a-zA-Z0-9-]+$ ]] || die "Invalid subdomain"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Invalid domain"

FQDN="$SUB.$DOMAIN"
SHORT_HOST="${FQDN%%.*}"

PUBLIC_IP=""
for s in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
  PUBLIC_IP=$(curl -4 -s --max-time 5 "$s" 2>/dev/null || true)
  [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
done
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(hostname -I | awk '{print $1}')
[[ -z "$PUBLIC_IP" ]] && die "Public IP detection failed"

hostnamectl set-hostname "$FQDN" || die "Failed to set hostname"
grep -q "^127.0.0.1" /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts
grep -v -w "$FQDN" /etc/hosts > /etc/hosts.tmp && mv /etc/hosts.tmp /etc/hosts
echo "$PUBLIC_IP $FQDN $SHORT_HOST" >> /etc/hosts

# Preseed postfix
echo "postfix postfix/mailname string $DOMAIN" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections

ok "FQDN set to $FQDN ($PUBLIC_IP)"

# ========================= Base Packages =========================
apt update -y && apt upgrade -y
apt install -y curl gnupg ca-certificates apt-transport-https \
zip unzip tar rsync jq unattended-upgrades default-mysql-client ufw fail2ban
ok "Base packages installed"

# ========================= Smart Port Check =========================
for p in 80 443 8443 3306; do
  if ss -lntp | grep -q ":$p "; then
    SERVICE=$(ss -lntp | grep ":$p " | awk '{print $NF}')
    warn "Port $p in use by $SERVICE"
    die "Clean VPS required"
  fi
done
ok "Ports are free"

# ========================= Swap Adaptive =========================
if ! swapon --show | grep -q swap; then
  RAM=$(free -m | awk '/Mem:/ {print $2}')
  SIZE="2G"; [[ "$RAM" -gt 2048 ]] && SIZE="1G"
  fallocate -l $SIZE /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

# ========================= Install CloudPanel =========================
info "Installing CloudPanel..."
curl -fsSL https://installer.cloudpanel.io/ce/v2/install.sh -o /tmp/clp.sh
bash /tmp/clp.sh || die "CloudPanel install failed"
rm -f /tmp/clp.sh
sleep 5
systemctl is-active --quiet clp-agent || die "CloudPanel service failed"
ok "CloudPanel installed"

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

# ========================= MariaDB Adaptive =========================
RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
BP=$((RAM_MB/4))
[[ $BP -lt 256 ]] && BP=256
cat > /etc/mysql/mariadb.conf.d/99-enterprise.cnf <<EOF
[mysqld]
innodb_buffer_pool_size=${BP}M
innodb_log_file_size=64M
max_connections=30
tmp_table_size=32M
max_heap_table_size=32M
EOF
systemctl restart mariadb || true
ok "MariaDB tuned (${BP}M buffer pool)"

# ========================= PHP-FPM Adaptive =========================
for DIR in /etc/php/*/fpm/pool.d; do
  [ -d "$DIR" ] || continue
  sed -i "s/^pm.max_children.*/pm.max_children = 4/" $DIR/*.conf || true
done
systemctl restart php*-fpm 2>/dev/null || true
ok "PHP-FPM tuned"

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
systemctl enable fail2ban
systemctl restart fail2ban
ok "Fail2Ban active"

# ========================= Final =========================
IP=$(hostname -I | awk '{print $1}')
echo
info "═══════════════════════════════════════════"
ok  "CloudPanel Enterprise Ready"
ok  "Access: https://$IP:8443"
ok  "FQDN  : $FQDN"
info "Reboot recommended"
info "═══════════════════════════════════════════"
