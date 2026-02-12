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

read -rp "Enter hostname (e.g. vps): " HOSTNAME
read -rp "Enter domain name (e.g. example.com): " DOMAIN
read -rp "Enter admin email (SSL alerts): " ADMIN_EMAIL

[[ -n "$HOSTNAME" && -n "$DOMAIN" && -n "$ADMIN_EMAIL" ]] \
  || die "Inputs cannot be empty"

[[ "$DOMAIN" =~ \. ]] || die "Invalid domain format"
[[ "$ADMIN_EMAIL" =~ @ ]] || die "Invalid email format"

FQDN="${HOSTNAME}.${DOMAIN}"

rept "Input validated"

# ==============================================================================
# DNS A Record Validation
# ==============================================================================
info "Validating DNS A record..."

SERVER_IP="$(curl -fsSL https://api.ipify.org || true)"
DNS_IP="$(dig +short "$FQDN" A | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)"

[[ -n "$SERVER_IP" ]] || die "Cannot detect server public IP"

if [[ "$SERVER_IP" != "$DNS_IP" ]]; then
  warn "DNS A record mismatch detected"
  warn "Server IP : $SERVER_IP"
  warn "DNS IP    : ${DNS_IP:-NOT FOUND}"
  die "Fix DNS A record before issuing certificate"
fi

rept "DNS A record verified"

# ==============================================================================
# Smart Basic System Preparation (Production Ready)
# ==============================================================================
info "Preparing base system (smart mode)..."

# Detect Primary Public IPv4
PUBLIC_IPV4=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')

if [[ -z "$PUBLIC_IPV4" ]] || [[ "$PUBLIC_IPV4" =~ ^10\. ]] || \
   [[ "$PUBLIC_IPV4" =~ ^192\.168\. ]] || [[ "$PUBLIC_IPV4" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
    warn "Public IPv4 not detected or behind NAT. Using 127.0.1.1 fallback."
    PUBLIC_IPV4="127.0.1.1"
else
    success "Detected Public IPv4: $PUBLIC_IPV4"
fi

# Detect IPv6 (if exists)
PUBLIC_IPV6=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{print $7; exit}')

if [[ -n "$PUBLIC_IPV6" ]]; then
    success "Detected IPv6: $PUBLIC_IPV6"
else
    info "No IPv6 detected. Skipping IPv6 host entry."
fi

CURRENT_HOSTNAME=$(hostnamectl --static)

if [[ "$CURRENT_HOSTNAME" != "$FQDN" ]]; then
    hostnamectl set-hostname "$FQDN"
    success "Hostname updated to $FQDN"
else
    info "Hostname already set correctly."
fi

cp /etc/hosts /etc/hosts.bak.$(date +%s)

# Remove old entries for this hostname
sed -i "/$FQDN/d" /etc/hosts

# Ensure localhost entries exist
grep -q "^127.0.0.1" /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts
grep -q "^::1" /etc/hosts || echo "::1 localhost ip6-localhost ip6-loopback" >> /etc/hosts

# Add IPv4 entry
echo "$PUBLIC_IPV4 $FQDN ${FQDN%%.*}" >> /etc/hosts

# Add IPv6 entry if available
if [[ -n "$PUBLIC_IPV6" ]]; then
    echo "$PUBLIC_IPV6 $FQDN ${FQDN%%.*}" >> /etc/hosts
fi

success "/etc/hosts updated safely."

info "Final hostname: $(hostname)"
info "Hostname -f: $(hostname -f)"
info "IPv4: $PUBLIC_IPV4"
[[ -n "$PUBLIC_IPV6" ]] && info "IPv6: $PUBLIC_IPV6"

success "Base system preparation completed."

# ==============================================================================
# Set Timezone
# ==============================================================================

if timedatectl list-timezones | grep -q "^$TIMEZONE$"; then
    timedatectl set-timezone "$TIMEZONE"
    success "Timezone set to $TIMEZONE"
else
    warn "Timezone $TIMEZONE not valid. Skipping."
fi

# ==============================================================================
# Basic System Installation
# ==============================================================================
info "Preparing basic installation..."

apt-get update || die "APT update failed"
apt-get upgrade -y || die "System upgrade failed"

apt-get install -y \
  curl wget git unzip \
  ca-certificates gnupg lsb-release \
  dnsutils certbot vnstat

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

unset HOSTNAME DOMAIN FQDN ADMIN_EMAIL SERVER_IP DNS_IP TIMEZONE
