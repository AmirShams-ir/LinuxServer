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
# OS Detection
# ==============================================================================
source /etc/os-release || { echo "Cannot detect OS."; exit 1; }

[[ "${ID}" == "debian" || "${ID}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* ]] \
  || { echo "Debian/Ubuntu only."; exit 1; }

OS_ID="$ID"
OS_VER="$VERSION_ID"
PRETTY="$PRETTY_NAME"

MAIN_LIST="/etc/apt/sources.list"
IR_LIST="/etc/apt/sources.list.d/ir-mirrors.list"
PIN_FILE="/etc/apt/preferences.d/99-mirror-priority"
APT_CONF="/etc/apt/apt.conf.d/99-fast-retries"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
cp -a "$MAIN_LIST" "${MAIN_LIST}.bak.${TIMESTAMP}"

echo "Detected OS: $PRETTY"
echo "Backup created."

# ==============================================================================
# Debian
# ==============================================================================
if [[ "$OS_ID" == "debian" ]]; then

  case "$OS_VER" in
    12) CODENAME="bookworm"; COMPONENTS="main contrib non-free non-free-firmware" ;;
    13) CODENAME="trixie"; COMPONENTS="main contrib non-free non-free-firmware" ;;
    *)  echo "Unsupported Debian version"; exit 1 ;;
  esac

  # --- Official (Fallback) ---
  cat > "$MAIN_LIST" <<EOF
deb https://deb.debian.org/debian $CODENAME $COMPONENTS
deb https://deb.debian.org/debian $CODENAME-updates $COMPONENTS
deb https://deb.debian.org/debian-security $CODENAME-security $COMPONENTS
EOF

  # --- IR Mirrors (Primary) ---
  cat > "$IR_LIST" <<EOF
deb http://mirror.cdn.ir/repository/debian $CODENAME $COMPONENTS
deb http://mirror.cdn.ir/repository/debian $CODENAME-updates $COMPONENTS
deb http://mirror.cdn.ir/repository/debian-security $CODENAME-security $COMPONENTS

deb http://repo.iut.ac.ir/debian $CODENAME $COMPONENTS
deb http://repo.iut.ac.ir/debian $CODENAME-updates $COMPONENTS

deb http://mirror.arvancloud.ir/debian $CODENAME $COMPONENTS
deb http://mirror.arvancloud.ir/debian-security $CODENAME-security $COMPONENTS
EOF

  # --- Pinning ---
  mkdir -p /etc/apt/preferences.d
  cat > "$PIN_FILE" <<EOF
Package: *
Pin: origin edge02.10.ir.cdn.ir
Pin-Priority: 900

Package: *
Pin: origin repo.iut.ac.ir
Pin-Priority: 850

Package: *
Pin: origin mirror.arvancloud.ir
Pin-Priority: 800

Package: *
Pin: origin deb.debian.org
Pin-Priority: 400

# ==============================================================================
# Ubuntu
# ==============================================================================
if [[ "$OS_ID" == "ubuntu" ]]; then

  case "$OS_VER" in
    22.04) CODENAME="jammy" ;;
    24.04) CODENAME="noble" ;;
    *) echo "Unsupported Ubuntu version"; exit 1 ;;
  esac

  cat > "$MAIN_LIST" <<EOF
deb https://archive.ubuntu.com/ubuntu $CODENAME main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu $CODENAME-updates main restricted universe multiverse
deb https://security.ubuntu.com/ubuntu $CODENAME-security main restricted universe multiverse
EOF

  cat > "$IR_LIST" <<EOF
deb http://mirror.cdn.ir/ubuntu $CODENAME main restricted universe multiverse
deb http://mirror.cdn.ir/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://mirror.cdn.ir/ubuntu $CODENAME-security main restricted universe multiverse

deb http://repo.iut.ac.ir/ubuntu $CODENAME main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu $CODENAME-security main restricted universe multiverse

deb http://mirror.arvancloud.ir/ubuntu $CODENAME main restricted universe multiverse
EOF

  mkdir -p /etc/apt/preferences.d
  cat > "$PIN_FILE" <<EOF
Package: *
Pin: origin mirror.cdn.ir
Pin-Priority: 900

Package: *
Pin: origin repo.iut.ac.ir
Pin-Priority: 850

Package: *
Pin: origin mirror.arvancloud.ir
Pin-Priority: 800

Package: *
Pin: origin archive.ubuntu.com
Pin-Priority: 400

Package: *
Pin: origin security.ubuntu.com
Pin-Priority: 400
EOF
fi

# ==============================================================================
# Failover Speed Tuning
# ==============================================================================
cat > "$APT_CONF" <<EOF
Acquire::Retries "5";
Acquire::http::Timeout "15";
Acquire::https::Timeout "15";
Acquire::Queue-Mode "access";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

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
