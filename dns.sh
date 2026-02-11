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
  command -v sudo >/dev/null 2>&1 || exit 1
  exec sudo -E bash "$0" "$@"
fi

# ==============================================================================
# OS detection
# ==============================================================================
source /etc/os-release

IS_UBUNTU=false
IS_DEBIAN=false

case "$ID" in
  ubuntu) IS_UBUNTU=true ;;
  debian) IS_DEBIAN=true ;;
esac

$IS_UBUNTU || $IS_DEBIAN ||  echo "❌ ERROR: Unsupported OS. Debian/Ubuntu only." exit 1

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/server-dns.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

log() { echo -e "\e[32m[✔] $1\e[0m"; }
die() { echo -e "\e[31m[✖] $1\e[0m"; }

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Smart DNS Server Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# ==============================================================================
# DNS CONFIG
# ==============================================================================
INTL_DNS=(
  1.1.1.1 1.0.0.1 9.9.9.9 149.112.112.112 8.8.8.8 4.2.2.4
)

IR_DNS=(
  185.51.200.2 178.22.122.100 78.157.42.100 78.157.42.101
  185.55.225.24 185.55.225.25 185.55.225.26 181.41.194.177 181.41.194.186
  94.103.125.157 94.103.125.158 209.244.0.3 209.244.0.4 5.200.200.200
  217.218.127.127 217.218.155.155 87.107.110.109 87.107.110.110
)

PING_TIMEOUT=1

measure_latency() {
  ping -c1 -W"$PING_TIMEOUT" "$1" 2>/dev/null \
    | awk -F'/' 'END {print $5}' || true
}

INTL_SORTED=()
IR_SORTED=()

log "Testing latency for international DNS servers..."
for d in "${INTL_DNS[@]}"; do
  l=$(measure_latency "$d")
  [[ -n "$l" ]] && INTL_SORTED+=("$l:$d") && echo "  ✔ $d → ${l} ms"
done

log "Testing latency for Iranian DNS servers..."
for d in "${IR_DNS[@]}"; do
  l=$(measure_latency "$d")
  [[ -n "$l" ]] && IR_SORTED+=("$l:$d") && echo "  ✔ $d → ${l} ms"
done

if [[ "${#INTL_SORTED[@]}" -gt 0 ]]; then
  DNS_PRIMARY=$(printf "%s\n" "${INTL_SORTED[@]}" | sort -n | cut -d: -f2)
  DNS_FALLBACK=$(printf "%s\n" "${IR_SORTED[@]}" | sort -n | cut -d: -f2)
else
  die "[!] National internet mode detected"
  DNS_PRIMARY=$(printf "%s\n" "${IR_SORTED[@]}" | sort -n | cut -d: -f2)
  DNS_FALLBACK=("${INTL_DNS[@]}")
fi

[[ -z "$DNS_PRIMARY" ]] && exit 1

# ==============================================================================
# APPLY DNS
# ==============================================================================
log "Applying DNS configuration"

if $IS_UBUNTU && command -v resolvectl >/dev/null 2>&1; then
  mkdir -p /etc/systemd/resolved.conf.d

  cat > /etc/systemd/resolved.conf.d/10-smart-dns.conf <<EOF
[Resolve]
DNS=$(echo "$DNS_PRIMARY")
FallbackDNS=$(echo "$DNS_FALLBACK")
DNSOverTLS=opportunistic
DNSSEC=no
EOF

  systemctl enable systemd-resolved >/dev/null 2>&1 || true
  systemctl restart systemd-resolved
  resolvectl flush-caches

  IFACE=$(ip route | awk '/default/ {print $5; exit}')
  resolvectl revert "$IFACE" || true
  resolvectl dns "$IFACE" $DNS_PRIMARY
  resolvectl domain "$IFACE" ~.

  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

else
  cat > /etc/resolv.conf <<EOF
$(for d in $DNS_PRIMARY $DNS_FALLBACK; do echo "nameserver $d"; done)
options edns0
EOF
fi

log "DNS configured successfully"

# ==============================================================================
# CLEANUP
# ==============================================================================
apt-get autoremove -y
apt-get autoclean -y
unset INTL_DNS IR_DNS INTL_SORTED IR_SORTED DNS_PRIMARY DNS_FALLBACK IS_UBUNTU IS_DEBIAN
log "Cleanup successfully"

# ==============================================================================
# REPORT
# ==============================================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ Smart DNS Resolver : ACTIVE\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo

if command -v resolvectl >/dev/null 2>&1; then
  resolvectl status
else
  cat /etc/resolv.conf
fi
log "══════════════════════════════════════════════"
