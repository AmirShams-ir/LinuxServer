#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Configure official APT repositories with prioritized fallback
#              mirrors for Debian/Ubuntu VPS environments.
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
info "✔ Repository Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Root Check
# ==============================================================================
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

source /etc/os-release || { echo "OS detection failed."; exit 1; }

[[ "$ID" == "debian" ]] || { echo "Debian only."; exit 1; }

case "$VERSION_ID" in
  11) CODENAME="bullseye"; COMPONENTS="main contrib non-free" ;;
  12) CODENAME="bookworm"; COMPONENTS="main contrib non-free non-free-firmware" ;;
  *) echo "Unsupported Debian version"; exit 1 ;;
esac

echo "Detected: $PRETTY_NAME"

# ==============================================================================
# Backup
# ==============================================================================
TS=$(date +%Y%m%d-%H%M%S)
cp -a /etc/apt/sources.list /etc/apt/sources.list.bak.$TS

# ==============================================================================
# Official (Fallback Only)
# ==============================================================================
cat > /etc/apt/sources.list <<EOF
deb https://deb.debian.org/debian $CODENAME $COMPONENTS
deb https://deb.debian.org/debian $CODENAME-updates $COMPONENTS
deb https://deb.debian.org/debian-security ${CODENAME}-security $COMPONENTS
EOF

# ==============================================================================
# IR Mirrors (Primary including security)
# ==============================================================================
cat > /etc/apt/sources.list.d/ir-primary.list <<EOF
deb http://repo.iut.ac.ir/debian $CODENAME $COMPONENTS
deb http://repo.iut.ac.ir/debian $CODENAME-updates $COMPONENTS
deb http://repo.iut.ac.ir/debian-security ${CODENAME}-security $COMPONENTS

deb http://mirror.arvancloud.ir/debian $CODENAME $COMPONENTS
deb http://mirror.arvancloud.ir/debian-updates $CODENAME-updates $COMPONENTS
deb http://mirror.arvancloud.ir/debian-security ${CODENAME}-security $COMPONENTS
EOF

# ==============================================================================
# Pinning (NO 990 to avoid skew)
# ==============================================================================
mkdir -p /etc/apt/preferences.d

cat > /etc/apt/preferences.d/priority <<EOF
Package: *
Pin: origin repo.iut.ac.ir
Pin-Priority: 900

Package: *
Pin: origin mirror.arvancloud.ir
Pin-Priority: 900

Package: *
Pin: origin deb.debian.org
Pin-Priority: 400
EOF

# ==============================================================================
# Fast Failover Config
# ==============================================================================
cat > /etc/apt/apt.conf.d/99-fast <<EOF
Acquire::Retries "5";
Acquire::http::Timeout "15";
Acquire::https::Timeout "15";
Acquire::Queue-Mode "access";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

# ==============================================================================
# Clean Broken State
# ==============================================================================
info "Cleaning APT state..."

apt-get clean
apt-mark unhold $(apt-mark showhold 2>/dev/null) 2>/dev/null || true

dpkg --configure -a || true
apt --fix-broken install -y || true

# ==============================================================================
# Update & Upgrade Safely
# ==============================================================================
info "Updating package index..."
apt-get update

echo "Running full upgrade..."
apt-get -o Dpkg::Options::="--force-confnew" full-upgrade -y

# ==============================================================================
# Verification
# ==============================================================================
info "========== VERIFY =========="
apt-cache policy bash | sed -n '1,15p'
info "============================"

# ==============================================================================
# Clean & Update
# ==============================================================================
apt-get clean
apt-get update

apt-cache policy bash | sed -n '1,12p'

# ==============================================================================
# Final Summary
# ==============================================================================
info "══════════════════════════════════════════════"
rept "OS       : $PRETTY"
rept "Primary  : Mirror repositories (IR)"
rept "Fallback : Official repositories (US)"
info "══════════════════════════════════════════════"

unset PRETTY OS_ID OS_VER MAIN_LIST IR_LIST PIN_FILE
