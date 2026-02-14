#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Private DNS Server and harden a fresh Debian/Ubuntu VPS.
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


info "Installing Unbound..."
apt update -y
apt install -y unbound

info "Creating optimized configuration..."

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
    prefetch-key: yes
    serve-expired: yes
    serve-expired-ttl: 86400
    serve-expired-reply-ttl: 30

    # Security hardening
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    unwanted-reply-threshold: 10000000
    qname-minimisation: yes

    # DNSSEC
    auto-trust-anchor-file: "/var/lib/unbound/root.key"

    # IPv4 only
    do-ip4: yes
    do-ip6: no

    # Improve reliability
    edns-buffer-size: 1232

forward-zone:
    name: "."
    forward-first: yes

    # Cloudflare
    forward-addr: 1.1.1.1
    forward-addr: 1.0.0.1

    # Google
    forward-addr: 8.8.8.8
    forward-addr: 8.8.4.4

    # Quad9
    forward-addr: 9.9.9.9
EOF

info "Downloading root trust anchor..."
unbound-anchor -a "/var/lib/unbound/root.key" || true

info "Setting system resolver to 127.0.0.1..."

# Disable systemd-resolved if active
if systemctl is-active --quiet systemd-resolved; then
    systemctl disable systemd-resolved
    systemctl stop systemd-resolved
    rm -f /etc/resolv.conf
fi

echo "nameserver 127.0.0.1" > /etc/resolv.conf

chattr +i /etc/resolv.conf 2>/dev/null || true

echo "[+] Restarting Unbound..."
systemctl enable unbound
systemctl restart unbound

sleep 2

info "Testing resolution..."
dig google.com @127.0.0.1 +short || true

info "══════════════════════════════════════════════════"
rept " DNS setup completed successfully."
rept " Primary DNS: 127.0.0.1"
rept " Upstreams: Cloudflare / Google / Quad9"
info "══════════════════════════════════════════════════"
