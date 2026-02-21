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
info "✔ CloudPanel Script Install And Optimize"
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
apt -y install curl wget sudo unattended-upgrades default-mysql-client

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

ok "ُSwap installed"

# ========================= Install CloudPanel =========================
info "Installing CloudPanel..."
curl -sS https://installer.cloudpanel.io/ce/v2/install.sh -o install.sh; \
echo "19cfa702e7936a79e47812ff57d9859175ea902c62a68b2c15ccd1ebaf36caeb install.sh" | \
sha256sum -c && DB_ENGINE=MARIADB_10.11 bash install.sh

ok "CloudPanel installed"
rm install.sh

# ========================= Final =========================
IP=$(hostname -I | awk '{print $1}')

info "═══════════════════════════════════════════"
ok  "CloudPanel Enterprise Ready"
ok  "Access: https://$IP:8443"
ok  "FQDN  : $FQDN"
info "Reboot recommended"
info "═══════════════════════════════════════════"
