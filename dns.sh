#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Smart DNS auto-selection based on latency (Debian/Ubuntu).
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

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Smart DNS Server Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# DNS Configuration
# ==============================================================================
info "Preparing DNS server lists..."

INTL_DNS=(1.1.1.1 1.0.0.1 9.9.9.9 149.112.112.112 8.8.8.8 4.2.2.4)
IR_DNS=(185.51.200.2 178.22.122.100 78.157.42.100 78.157.42.101
        185.55.225.24 185.55.225.25 185.55.225.26
        94.103.125.157 94.103.125.158 217.218.127.127)

PING_TIMEOUT=1

measure_latency() {
  ping -c1 -W"$PING_TIMEOUT" "$1" 2>/dev/null \
    | awk -F'/' 'END {print $5}' || true
}

rept "DNS server lists prepared"

# ==============================================================================
# Latency Testing
# ==============================================================================
info "Measuring DNS latency..."

INTL_SORTED=()
IR_SORTED=()

for d in "${INTL_DNS[@]}"; do
  l="$(measure_latency "$d")"
  [[ -n "$l" ]] && INTL_SORTED+=("$l:$d")
done

for d in "${IR_DNS[@]}"; do
  l="$(measure_latency "$d")"
  [[ -n "$l" ]] && IR_SORTED+=("$l:$d")
done

rept "Latency measurement completed"

# ==============================================================================
# DNS Selection Logic
# ==============================================================================
info "Selecting optimal DNS servers..."

if [[ ${#INTL_SORTED[@]} -gt 0 ]]; then
  DNS_PRIMARY="$(printf "%s\n" "${INTL_SORTED[@]}" | sort -n | head -n1 | cut -d: -f2)"
  DNS_FALLBACK="$(printf "%s\n" "${IR_SORTED[@]}" | sort -n | head -n1 | cut -d: -f2 || true)"
else
  warn "International DNS unreachable. Using national mode."
  DNS_PRIMARY="$(printf "%s\n" "${IR_SORTED[@]}" | sort -n | head -n1 | cut -d: -f2 || true)"
  DNS_FALLBACK=""
fi

[[ -n "$DNS_PRIMARY" ]] || die "No reachable DNS servers found"

rept "Primary DNS selected: $DNS_PRIMARY"

# ==============================================================================
# Apply DNS Configuration
# ==============================================================================
info "Applying DNS configuration..."

if command -v resolvectl >/dev/null 2>&1; then

  mkdir -p /etc/systemd/resolved.conf.d

  cat > /etc/systemd/resolved.conf.d/10-smart-dns.conf <<EOF
[Resolve]
DNS=$DNS_PRIMARY
FallbackDNS=$DNS_FALLBACK
DNSOverTLS=opportunistic
DNSSEC=no
EOF

  systemctl enable systemd-resolved >/dev/null 2>&1 || true
  systemctl restart systemd-resolved
  resolvectl flush-caches

  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

else

  {
    echo "nameserver $DNS_PRIMARY"
    [[ -n "$DNS_FALLBACK" ]] && echo "nameserver $DNS_FALLBACK"
    echo "options edns0"
  } > /etc/resolv.conf

fi

rept "DNS configured successfully"

# ==============================================================================
# Cleanup
# ==============================================================================
info "Performing cleanup..."

apt-get autoremove -y >/dev/null
apt-get autoclean -y >/dev/null

unset INTL_DNS IR_DNS INTL_SORTED IR_SORTED DNS_PRIMARY DNS_FALLBACK

rept "Cleanup completed"

# ==============================================================================
# Final Summary
# ==============================================================================
info "═══════════════════════════════════════════"
rept "Smart DNS Resolver Activated"
info "═══════════════════════════════════════════"

if command -v resolvectl >/dev/null 2>&1; then
  resolvectl status | sed -n '1,20p'
else
  cat /etc/resolv.conf
fi
