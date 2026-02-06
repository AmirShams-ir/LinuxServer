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
# Root / sudo handling
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$0" "$@"
  else
    exit 1
  fi
fi

# ==============================================================================
# OS validation
# ==============================================================================
if [[ ! -f /etc/os-release ]] || \
   ! grep -Eqi '^(ID=(debian|ubuntu)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  exit 1
fi

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/server-dns.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ DNS Server Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# --------------------------------------------------
# GLOBAL CONFIG
# --------------------------------------------------
INTL_DNS=(
  "1.1.1.1"
  "1.0.0.1"
  "9.9.9.9"
  "149.112.112.112"
  "8.8.8.8"
  "4.2.2.4"
)

IR_DNS=(
  "185.51.200.2"
  "178.22.122.100"
  "10.202.10.102"
  "10.202.10.202"
  "185.55.225.25"
  "185.55.225.26"
  "181.41.194.177"
  "181.41.194.186"
)

PING_TIMEOUT=1

# --------------------------------------------------
# HELPERS
# --------------------------------------------------
log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

measure_latency() {
  ping -c1 -W"$PING_TIMEOUT" "$1" 2>/dev/null \
    | awk -F'/' 'END {print $5}'
}

# --------------------------------------------------
# LATENCY SORTING
# --------------------------------------------------
log "Testing latency for international DNS servers..."

INTL_SORTED=()
for dns in "${INTL_DNS[@]}"; do
  lat=$(measure_latency "$dns")
  [[ -n "$lat" ]] && INTL_SORTED+=("$lat:$dns") && echo "  ✔ $dns → ${lat} ms"
done

log "Testing latency for Iranian DNS servers..."
IR_SORTED=()
for dns in "${IR_DNS[@]}"; do
  lat=$(measure_latency "$dns")
  [[ -n "$lat" ]] && IR_SORTED+=("$lat:$dns") && echo "  ✔ $dns → ${lat} ms"
done

DNS_PRIMARY=$(printf "%s\n" "${INTL_SORTED[@]}" | sort -n | cut -d: -f2 | tr '\n' ' ')
DNS_FALLBACK=$(printf "%s\n" "${IR_SORTED[@]}"   | sort -n | cut -d: -f2 | tr '\n' ' ')

[[ -z "$DNS_PRIMARY" ]] && die "No international DNS responded."

# --------------------------------------------------
# DNS CONFIG (SAFE MODE)
# --------------------------------------------------
log "Configuring system DNS resolver"

if systemctl list-unit-files | grep -q '^systemd-resolved\.service'; then
  log "systemd-resolved detected"

  mkdir -p /etc/systemd/resolved.conf.d

  cat > /etc/systemd/resolved.conf.d/10-latency-dns.conf <<EOF
[Resolve]
DNS=${DNS_PRIMARY}
FallbackDNS=${DNS_FALLBACK}
DNSOverTLS=opportunistic
DNSSEC=no
Cache=yes
EOF

  systemctl enable systemd-resolved >/dev/null 2>&1 || true
  systemctl restart systemd-resolved
  resolvectl flush-caches

  # ---- HARD LINK OVERRIDE (prevent DHCP DNS injection) ----
  resolvectl revert eth0 || true
  resolvectl dns eth0 $DNS_PRIMARY
  resolvectl domain eth0 ~.

  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

else
  log "systemd-resolved not found, falling back to /etc/resolv.conf"

  cat > /etc/resolv.conf <<EOF
$(for d in $DNS_PRIMARY $DNS_FALLBACK; do echo "nameserver $d"; done)
options edns0
EOF
fi

# --------------------------------------------------
# CLEANUP
# --------------------------------------------------
log "Cleanup"
apt-get autoremove -y
apt-get autoclean -y
unset INTL_DNS IR_DNS INTL_SORTED IR_SORTED DNS_PRIMARY DNS_FALLBACK

# ==================================================
# FINAL REPORT
# ==================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ DNS-Server    : OK\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo
resolvectl status
