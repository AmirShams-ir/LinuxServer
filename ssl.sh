#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: TLS/SSL bootstrap with DNS validation (Certbot standalone)
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
    exec sudo --preserve-env=PATH bash "$0" "$@"
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

TIMEZONE="UTC"

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ TLS/SSL Bootstrap Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Input
# ==============================================================================
info "Collecting user input..."

read -rp "Enter hostname (e.g. vps): " HOST_SHORT
read -rp "Enter domain name (e.g. example.com): " DOMAIN
read -rp "Enter admin email (SSL alerts): " ADMIN_EMAIL

[[ -n "$HOST_SHORT" && -n "$DOMAIN" && -n "$ADMIN_EMAIL" ]] \
  || die "Inputs cannot be empty"

[[ "$DOMAIN" =~ \. ]] || die "Invalid domain format"
[[ "$ADMIN_EMAIL" =~ @ ]] || die "Invalid email format"

FQDN="${HOST_SHORT}.${DOMAIN}"

rept "Input validated"

# ==============================================================================
# Install minimal DNS tools (if missing)
# ==============================================================================
if ! command -v dig >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y dnsutils
fi

# ==============================================================================
# DNS A Record Validation
# ==============================================================================
info "Validating DNS A record..."

SERVER_IP=$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')
DNS_IP=$(dig +short "$FQDN" A | head -n1 || true)

[[ -n "$SERVER_IP" ]] || die "Cannot detect server IP"

if [[ "$SERVER_IP" != "$DNS_IP" ]]; then
  warn "DNS A record mismatch detected"
  warn "Server IP : $SERVER_IP"
  warn "DNS IP    : ${DNS_IP:-NOT FOUND}"
  die "Fix DNS A record before issuing certificate"
fi

rept "DNS A record verified"

# ==============================================================================
# Smart Hostname Configuration
# ==============================================================================
info "Configuring hostname..."

CURRENT_HOSTNAME=$(hostnamectl --static)

if [[ "$CURRENT_HOSTNAME" != "$FQDN" ]]; then
  hostnamectl set-hostname "$FQDN"
  rept "Hostname updated to $FQDN"
else
  info "Hostname already set correctly."
fi

cp /etc/hosts /etc/hosts.bak.$(date +%s)
sed -i "/$FQDN/d" /etc/hosts

grep -q "^127.0.0.1" /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts
grep -q "^::1" /etc/hosts || echo "::1 localhost ip6-localhost ip6-loopback" >> /etc/hosts

echo "$SERVER_IP $FQDN ${FQDN%%.*}" >> /etc/hosts

rept "/etc/hosts updated"

# ==============================================================================
# Timezone
# ==============================================================================
if timedatectl list-timezones | grep -q "^$TIMEZONE$"; then
  timedatectl set-timezone "$TIMEZONE"
  rept "Timezone set to $TIMEZONE"
fi

# ==============================================================================
# Base Packages
# ==============================================================================
info "Installing base packages..."

apt-get update -y
apt-get upgrade -y

apt-get install -y \
  curl wget git unzip \
  ca-certificates gnupg lsb-release \
  certbot vnstat

rept "System prepared"

# ==============================================================================
# SSL Certificate (Standalone)
# ==============================================================================
info "Issuing SSL certificate..."

if systemctl is-active --quiet lsws; then
  systemctl stop lsws
  NEED_LSWS_RESTART=1
fi

certbot certonly \
  --standalone \
  --preferred-challenges http \
  --agree-tos \
  --non-interactive \
  -m "$ADMIN_EMAIL" \
  -d "$FQDN" \
  || die "Certbot failed"

[[ "${NEED_LSWS_RESTART:-0}" == "1" ]] && systemctl start lsws

rept "SSL certificate issued successfully"

# ==============================================================================
# Final Summary
# ==============================================================================
info "══════════════════════════════════════════════"
rept "Hostname : $FQDN"
rept "SSL/TLS  : Active"
rept "Monitor  : vnStat enabled"
info "══════════════════════════════════════════════"

unset HOST_SHORT DOMAIN FQDN ADMIN_EMAIL SERVER_IP DNS_IP TIMEZONE
