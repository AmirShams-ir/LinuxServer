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
info "✔ DNS Server Script Started"
info "═══════════════════════════════════════════"
# ==============================================================================
# Install
# ==============================================================================
info "Installing Unbound..."
apt update -y
apt install -y unbound dnsutils

# Stop systemd-resolved if exists (prevents port 53 conflict)
if systemctl is-active --quiet systemd-resolved; then
    info "Disabling systemd-resolved..."
    systemctl disable --now systemd-resolved
fi

# Remove default DNSSEC anchor (forwarder mode)
rm -f /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf 2>/dev/null || true

# ==============================================================================
# Write Optimized Config
# ==============================================================================
info "Writing optimized config..."

cat > /etc/unbound/unbound.conf.d/hosting.conf << 'EOF'
server:
    verbosity: 0
    interface: 127.0.0.1
    port: 53

    # Performance (1GB VPS optimized)
    num-threads: 1
    so-reuseport: yes
    msg-cache-size: 64m
    rrset-cache-size: 128m
    cache-min-ttl: 300
    cache-max-ttl: 86400
    prefetch: yes
    serve-expired: yes
    serve-expired-ttl: 86400

    # Faster failover
    infra-cache-numhosts: 10000
    outgoing-range: 256
    num-queries-per-thread: 2048

    # Security (lightweight)
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-referral-path: yes
    qname-minimisation: yes

    # Network tuning for Iran
    do-ip4: yes
    do-ip6: no
    edns-buffer-size: 1232
    unwanted-reply-threshold: 10000000

    # Stability during filtering
    do-not-query-localhost: no
    rrset-roundrobin: yes


# Forward zone with parallel racing
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
    forward-addr: 149.112.112.112
EOF

# ==============================================================================
# Validate Config
# ==============================================================================
info "Validating config..."
unbound-checkconf || { echo "Config error! Aborting."; exit 1; }


# ==============================================================================
# Smart Resolver Setup (Debian / Ubuntu Compatible)
# ==============================================================================
info "Configuring system resolver intelligently..."

# Remove immutable flag if exists
chattr -i /etc/resolv.conf 2>/dev/null || true

# If systemd-resolved exists → disable it safely
if systemctl list-unit-files | grep -q systemd-resolved; then
    if systemctl is-active --quiet systemd-resolved; then
        info "Disabling systemd-resolved..."
        systemctl disable --now systemd-resolved
    fi
fi

# If resolv.conf is symlink → replace it
if [ -L /etc/resolv.conf ]; then
    info "Replacing symlinked resolv.conf..."
    rm -f /etc/resolv.conf
fi

# Write local resolver
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Lock it to prevent overwrite
chattr +i /etc/resolv.conf 2>/dev/null || true

rept "System resolver set to 127.0.0.1 successfully."

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


info "══════════════════════════════════════════"
rept " DNS setup completed successfully."
rept " Mode: Local cache + Forward racing"
rept " Optimized for Iran network"
info "══════════════════════════════════════════"
