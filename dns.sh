#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Smart DNS auto-selection based on latency (INTL + IR separated)
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Root Handling
# ==============================================================================
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || exit 1
  exec sudo --preserve-env=PATH bash "$0" "$@"
fi

# ==============================================================================
# OS Validation
# ==============================================================================
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
else
  exit 1
fi

[[ "${ID}" == "debian" || "${ID}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* ]] \
  || exit 1

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
info "✔ Smart DNS Latency Optimizer Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# DNS Lists
# ==============================================================================
INTL_DNS=(1.1.1.1 1.0.0.1 9.9.9.9 149.112.112.112 8.8.8.8 4.2.2.4)

IR_DNS=(185.51.200.2 178.22.122.100 78.157.42.100 78.157.42.101
        185.55.225.24 185.55.225.25 185.55.225.26 5.200.200.200
        94.103.125.157 94.103.125.158 217.218.127.127 217.218.155.155
        87.107.110.109 87.107.110.110 10.202.10.10 10.202.10.11 5.202.100.100 5.202.100.101)

PING_TIMEOUT=1

measure_latency() {
  ping -c1 -W"$PING_TIMEOUT" "$1" 2>/dev/null \
    | awk -F'/' 'END {print $5}' || true
}

# ==============================================================================
# Measure International Latency
# ==============================================================================
info "Measuring latency for INTERNATIONAL DNS servers..."

INTL_RESULTS=()

for d in "${INTL_DNS[@]}"; do
  l=$(measure_latency "$d")
  if [[ -n "$l" ]]; then
    INTL_RESULTS+=("$l:$d")
    printf "  %s → %sms\n" "$d" "$l"
  fi
done

# ==============================================================================
# Measure Iranian Latency
# ==============================================================================
info "Measuring latency for IRANIAN DNS servers..."

IR_RESULTS=()

for d in "${IR_DNS[@]}"; do
  l=$(measure_latency "$d")
  if [[ -n "$l" ]]; then
    IR_RESULTS+=("$l:$d")
    printf "  %s → %sms\n" "$d" "$l"
  fi
done

# ==============================================================================
# Sorting Logic (Separate)
# ==============================================================================
info "Sorting DNS servers by latency..."

if [[ "${#INTL_RESULTS[@]}" -gt 0 ]]; then
  DNS_PRIMARY=($(printf "%s\n" "${INTL_RESULTS[@]}" | sort -n | cut -d: -f2))
  DNS_FALLBACK=($(printf "%s\n" "${IR_RESULTS[@]}" | sort -n | cut -d: -f2))
  rept "International DNS selected as PRIMARY"
else
  warn "International DNS unreachable → National mode"
  DNS_PRIMARY=($(printf "%s\n" "${IR_RESULTS[@]}" | sort -n | cut -d: -f2))
  DNS_FALLBACK=("${INTL_DNS[@]}")
fi

[[ "${#DNS_PRIMARY[@]}" -gt 0 ]] || die "No reachable DNS servers found"

# ==============================================================================
# Apply DNS
# ==============================================================================
info "Applying DNS configuration..."

if command -v resolvectl >/dev/null 2>&1; then

  mkdir -p /etc/systemd/resolved.conf.d

  cat > /etc/systemd/resolved.conf.d/10-smart-dns.conf <<EOF
[Resolve]
DNS=${DNS_PRIMARY[*]}
FallbackDNS=${DNS_FALLBACK[*]}
DNSOverTLS=opportunistic
DNSSEC=no
EOF

  systemctl enable systemd-resolved >/dev/null 2>&1 || true
  systemctl restart systemd-resolved
  resolvectl flush-caches
  rept "systemd-resolved updated"
  resolvectl status

else

  {
    for d in "${DNS_PRIMARY[@]}"; do
      echo "nameserver $d"
    done
    for d in "${DNS_FALLBACK[@]}"; do
      echo "nameserver $d"
    done
    echo "options edns0"
  } > /etc/resolv.conf

  rept "/etc/resolv.conf updated"
  cat /etc/resolv.conf
fi

# ==============================================================================
# Final Summary
# ==============================================================================
info "═══════════════════════════════════════════"
rept "Primary DNS   : Set"
rept "Fallback DNS  : Set"
info "═══════════════════════════════════════════"

# ==============================================================================
# Cleanup
# ==============================================================================
unset DNS_PRIMARY DNS_FALLBACK
