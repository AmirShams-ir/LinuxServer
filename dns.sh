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

# ==============================================================================
# Strict mode
# ==============================================================================
set -Eeuo pipefail

# ==============================================================================
# Root / sudo handling
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "🔐 Root privileges required. Please enter sudo password..."
    exec sudo -E bash "$0" "$@"
  else
    echo "❌ ERROR: This script must be run as root."
    exit 1
  fi
fi

# ==============================================================================
# OS validation
# ==============================================================================
if [[ ! -f /etc/os-release ]] || \
   ! grep -Eqi '^(ID=(debian|ubuntu)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "❌ ERROR: Unsupported OS. Debian/Ubuntu only."
  exit 1
fi

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/server-dns.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "[✔] Logging enabled: $LOG"

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ DNS Server Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# ==============================================================================
# CONFIG
# ==============================================================================

# International DNS 
INTL_DNS=(
  "1.1.1.1"        # Cloudflare
  "9.9.9.9"        # Quad9
  "8.8.8.8"        # Google
  "1.0.0.1"
  "149.112.112.112"
  "4.2.2.4"
)

# Iranian Bypass DNS 
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

MAX_PRIMARY=2
PING_TIMEOUT=1

# ==============================================================================
# HELPERS
# ==============================================================================
log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

measure_latency() {
  ping -c1 -W"$PING_TIMEOUT" "$1" 2>/dev/null \
    | awk -F'/' 'END {print $5}'
}

# ==============================================================================
# LATENCY TEST (INTERNATIONAL ONLY)
# ==============================================================================
log "Testing latency for international DNS servers..."

RESULTS=()

for dns in "${INTL_DNS[@]}"; do
  latency=$(measure_latency "$dns")
  if [[ -n "${latency:-}" ]]; then
    echo "  ✔ $dns → ${latency} ms"
    RESULTS+=("$dns:$latency")
  else
    warn "$dns did not respond"
  fi
done

[[ "${#RESULTS[@]}" -eq 0 ]] && die "No international DNS responded."

PRIMARY_DNS=$(
  printf "%s\n" "${RESULTS[@]}" \
  | sort -t: -k2 -n \
  | head -n "$MAX_PRIMARY" \
  | cut -d: -f1 \
  | tr '\n' ' '
)

log "Selected primary DNS: $PRIMARY_DNS"
log "Fallback DNS (Iran): ${IR_DNS[*]}"

# ==============================================================================
# APPLY systemd-resolved CONFIG (OVERRIDE DHCP)
# ==============================================================================
log "Configuring systemd-resolved (authoritative override)"

mkdir -p /etc/systemd/resolved.conf.d

cat > /etc/systemd/resolved.conf.d/10-smart-dns.conf <<EOF
[Resolve]
DNS=$PRIMARY_DNS
FallbackDNS=${IR_DNS[*]}
Domains=~.
DNSSEC=no
DNSOverTLS=opportunistic
EOF

systemctl enable systemd-resolved >/dev/null 2>&1 || true
systemctl restart systemd-resolved
resolvectl flush-caches

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# ==============================================================================
# CLEANUP
# ==============================================================================
log "Cleanup"

# Clear apt cache safely
if command -v apt-get >/dev/null 2>&1; then
  apt-get autoremove -y >/dev/null 2>&1 || true
  apt-get autoclean  -y >/dev/null 2>&1 || true
fi

# Unset sensitive / temporary variables
unset INTL_DNS
unset IR_DNS
unset RESULTS
unset PRIMARY_DNS
unset MAX_PRIMARY
unset PING_TIMEOUT
unset LOG

log "Cleanup completed"

# ==============================================================================
# FINAL REPORT
# ==============================================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ Smart DNS Resolver : ACTIVE\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo

resolvectl status
