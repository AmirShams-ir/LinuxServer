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

# --------------------------------------------------
# GLOBAL CONFIG
# --------------------------------------------------
TIMEZONE="UTC"

# Global DNS
DNS_MAIN1="1.1.1.1"
DNS_MAIN2="1.0.0.1"
DNS_MAIN3="9.9.9.9"
DNS_MAIN4="149.112.112.112"
DNS_MAIN5="8.8.8.8"
DNS_MAIN6="4.2.2.4"

# Iranian / Bypass DNS (Fallback)
DNS_LOCAL1="185.51.200.2"
DNS_LOCAL2="178.22.122.100"
DNS_LOCAL3="10.202.10.102"
DNS_LOCAL4="10.202.10.202"
DNS_LOCAL5="185.55.225.25"
DNS_LOCAL6="185.55.225.26"
DNS_LOCAL7="181.41.194.177"
DNS_LOCAL8="181.41.194.186"

# --------------------------------------------------
# HELPERS
# --------------------------------------------------
log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# --------------------------------------------------
# DNS CONFIG (SAFE MODE)
# --------------------------------------------------
log "Configuring system DNS resolver" 
if systemctl list-unit-files | grep -q systemd-resolved; 
then sed -i '/^\[Resolve\]/,$d' /etc/systemd/resolved.conf 2>/dev/null || true 
cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=${DNS_MAIN1} ${DNS_MAIN3} ${DNS_MAIN5} ${DNS_LOCAL1} ${DNS_LOCAL3} ${DNS_LOCAL5} ${DNS_LOCAL7}
FallbackDNS=${DNS_MAIN2} ${DNS_MAIN4} ${DNS_MAIN6} ${DNS_LOCAL2} ${DNS_LOCAL4} ${DNS_LOCAL6} ${DNS_LOCAL8}
DNSOverTLS=opportunistic
DNSSEC=no
Cache=yes
EOF

systemctl enable systemd-resolved
systemctl start systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved 
else 

cat > /etc/resolv.conf <<EOF
nameserver ${DNS_MAIN1}
nameserver ${DNS_MAIN2}
nameserver ${DNS_MAIN3}
nameserver ${DNS_MAIN4}
nameserver ${DNS_MAIN5}
nameserver ${DNS_MAIN6}
nameserver ${DNS_LOCAL1}
nameserver ${DNS_LOCAL2}
nameserver ${DNS_LOCAL3}
nameserver ${DNS_LOCAL4}
nameserver ${DNS_LOCAL5}
nameserver ${DNS_LOCAL6}
nameserver ${DNS_LOCAL7}
nameserver ${DNS_LOCAL8}
options edns0
EOF

fi

log "DNS configured successfully"

# --------------------------------------------------
# CLEANUP
# --------------------------------------------------
log "Cleanup"
apt-get autoremove -y
apt-get autoclean -y
unset TIMEZONE DEBIAN_FRONTEND
unset DNS_MAIN1 DNS_MAIN2 DNS_MAIN3 DNS_MAIN4 DNS_MAIN5 DNS_MAIN6
unset DNS_LOCAL1 DNS_LOCAL2 DNS_LOCAL3 DNS_LOCAL4 DNS_LOCAL5 DNS_LOCAL6 DNS_LOCAL7 DNS_LOCAL8

# ==================================================
# FINAL REPORT
# ==================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m ✔ DNS-Server    : OK\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo
resolvectl status