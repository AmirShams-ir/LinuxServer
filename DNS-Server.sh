#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: This script performs mandatory base hosting setup on a fresh
#              Linux VPS.
#
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
#
# Disclaimer: This script is provided for educational and informational
#             purposes only. Use it responsibly and in compliance with all
#             applicable laws and regulations.
#
# Note: This script is designed to be SAFE, IDEMPOTENT, and NON-DESTRUCTIVE.
#       Review before use. No application-level services are installed here.
# -----------------------------------------------------------------------------

set -Eeuo pipefail

# ==============================================================================
# Root / sudo
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$0" "$@"
  else
    echo "❌ Must be run as root"
    exit 1
  fi
fi

# ==============================================================================
# OS validation
# ==============================================================================
if [[ ! -f /etc/os-release ]] || \
   ! grep -Eqi '^(ID=(debian|ubuntu)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "❌ Debian/Ubuntu only"
  exit 1
fi

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/server-dns.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ==============================================================================
# DNS pools
# ==============================================================================
DNS_GLOBAL_PRIMARY=(1.1.1.1 9.9.9.9 8.8.8.8)
DNS_GLOBAL_SECONDARY=(1.0.0.1 149.112.112.112 4.2.2.4)

DNS_IRAN_POOL=(
  185.51.200.2
  178.22.122.100
  185.55.225.25
  185.55.225.26
  10.202.10.102
  10.202.10.202
  181.41.194.177
  181.41.194.186
)

LATENCY_THRESHOLD_MS=400
TIMEOUT_THRESHOLD=2

# ==============================================================================
# DNS latency check
# ==============================================================================
dns_latency_ok() {
  local dns="$1"
  resolvectl query . @"$dns" --timeout="${TIMEOUT_THRESHOLD}s" \
    >/dev/null 2>&1
}

log "Evaluating DNS responsiveness..."

ACTIVE_DNS=()
SLOW_GLOBAL=false

for dns in "${DNS_GLOBAL_PRIMARY[@]}"; do
  if dns_latency_ok "$dns"; then
    ACTIVE_DNS+=("$dns")
  else
    warn "Global DNS $dns is slow or unreachable"
    SLOW_GLOBAL=true
  fi
done

if [[ "${#ACTIVE_DNS[@]}" -eq 0 ]] || [[ "$SLOW_GLOBAL" == true ]]; then
  warn "Global DNS degraded, enabling Iran DNS pool"
  ACTIVE_DNS+=("${DNS_IRAN_POOL[@]}")
fi

# ==============================================================================
# systemd-resolved configuration
# ==============================================================================
log "Applying adaptive DNS configuration"

cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=${ACTIVE_DNS[*]}
FallbackDNS=${DNS_GLOBAL_SECONDARY[*]}
DNSOverTLS=opportunistic
DNSSEC=no
Cache=yes
EOF

systemctl enable systemd-resolved >/dev/null 2>&1
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# ==============================================================================
# APT hardening
# ==============================================================================
log "Hardening APT networking"

cat > /etc/apt/apt.conf.d/99network-safe <<EOF
Acquire::ForceIPv4 "true";
Acquire::http::Pipeline-Depth "0";
Acquire::https::Timeout "15";
Acquire::http::Timeout "15";
EOF

# ==============================================================================
# Final report
# ==============================================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ Smart adaptive DNS configured\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo
resolvectl status
