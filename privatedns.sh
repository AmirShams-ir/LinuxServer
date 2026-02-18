#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Private DNS Server (Unbound) a fresh Debian/Ubuntu VPS.
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

has_systemd() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Private DNS Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Install
# ==============================================================================
info "Installing Unbound..."
apt update -y
apt install -y unbound dnsutils

rm -f /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf 2>/dev/null || true

# ==============================================================================
# Write Config
# ==============================================================================
info "Writing optimized config..."

cat > /etc/unbound/unbound.conf.d/hosting.conf << 'EOF'
server:
    verbosity: 0
    interface: 127.0.0.1
    port: 53

    # Performance
    num-threads: 2
    so-reuseport: yes
    msg-cache-size: 128m
    rrset-cache-size: 256m
    cache-min-ttl: 300
    cache-max-ttl: 86400
    prefetch: yes
    serve-expired: yes

    # Security
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-referral-path: yes
    qname-minimisation: yes

    # IPv4 stable mode
    do-ip4: yes
    do-ip6: no

    edns-buffer-size: 1232

forward-zone:
    name: "."
    forward-first: yes

    forward-addr: 1.1.1.1
    forward-addr: 1.0.0.1
    forward-addr: 8.8.8.8
    forward-addr: 8.8.4.4
    forward-addr: 9.9.9.9
    forward-addr: 149.112.112.112
EOF

# ==============================================================================
# Validate Config Before Restart
# ==============================================================================
info "Validating config..."
unbound-checkconf || { echo "Config error! Aborting."; exit 1; }

# ==============================================================================
# Resolver Setup
# ==============================================================================
info "Setting system resolver..."

# Unlock resolv.conf if immutable
chattr -i /etc/resolv.conf 2>/dev/null || true

echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true

# ==============================================================================
# Start Service
# ==============================================================================
info "Restarting Unbound..."
systemctl enable unbound
systemctl restart unbound

sleep 2

# ==============================================================================
# Test
# ==============================================================================
info "Testing DNS..."
dig google.com @127.0.0.1 +short || echo "DNS test failed"

# ==============================================================================
# Reports
# ==============================================================================
info "══════════════════════════════════════════════════"
rept " DNS setup completed successfully."
rept " Primary DNS: 127.0.0.1"
rept " Upstreams: Cloudflare / Google / Quad9"
info "══════════════════════════════════════════════════"
