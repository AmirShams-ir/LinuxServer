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
# Basic System Preparation
# ==============================================================================
info "Preparing base system..."

hostnamectl set-hostname "$FQDN" || true
grep -q "$FQDN" /etc/hosts || echo "127.0.1.1 $FQDN $HOSTNAME" >> /etc/hosts
timedatectl set-timezone "$TIMEZONE" || true

apt-get update || die "APT update failed"
apt-get upgrade -y || die "System upgrade failed"

apt-get install -y \
  curl wget git unzip \
  ca-certificates gnupg lsb-release \
  dnsutils certbot vnstat

rept "System prepared"

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
# Network Monitor
# ==============================================================================
info "Configuring vnStat..."

systemctl enable --now vnstat

rept "Network monitor enabled"

# ==============================================================================
# Cleanup
# ==============================================================================
info "Performing cleanup..."

apt-get autoremove -y
apt-get autoclean -y

unset HOSTNAME DOMAIN FQDN ADMIN_EMAIL SERVER_IP DNS_IP TIMEZONE

rept "Cleanup completed"

# ==============================================================================
# Final Summary
# ==============================================================================
info "══════════════════════════════════════════════"
rept "Hostname : $FQDN"
rept "SSL/TLS  : Active"
rept "Monitor  : vnStat enabled"
info "══════════════════════════════════════════════"
