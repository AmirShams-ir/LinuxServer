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
# Variables
# ==============================================================================
OS_ID="$ID"
OS_VER="$VERSION_ID"
PRETTY="$PRETTY_NAME"

MAIN_LIST="/etc/apt/sources.list"
IR_LIST="/etc/apt/sources.list.d/ir-mirror.list"
PIN_FILE="/etc/apt/preferences.d/99-apt-priority"

[[ -f "$MAIN_LIST" ]] || die "sources.list not found"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
cp -a "$MAIN_LIST" "${MAIN_LIST}.bak.${TIMESTAMP}"

info "Detected OS: $PRETTY"
rept "Backup created: ${MAIN_LIST}.bak.${TIMESTAMP}"

# ==============================================================================
# Debian Configuration
# ==============================================================================
info "Applying repository configuration..."

if [[ "$OS_ID" == "debian" ]]; then

  case "$OS_VER" in
    11) CODENAME="bullseye"; COMPONENTS="main contrib non-free" ;;
    12) CODENAME="bookworm"; COMPONENTS="main contrib non-free non-free-firmware" ;;
    *)  die "Unsupported Debian version: $OS_VER" ;;
  esac

  cat > "$MAIN_LIST" <<EOF
deb https://deb.debian.org/debian $CODENAME $COMPONENTS
deb https://deb.debian.org/debian $CODENAME-updates $COMPONENTS
deb https://security.debian.org/debian-security ${CODENAME}-security $COMPONENTS
EOF

  cat > "$IR_LIST" <<EOF
deb http://repo.iut.ac.ir/debian $CODENAME $COMPONENTS
deb http://repo.iut.ac.ir/debian $CODENAME-updates $COMPONENTS
deb http://mirror.arvancloud.ir/debian $CODENAME $COMPONENTS
deb http://mirror.arvancloud.ir/debian-security $CODENAME-security $COMPONENTS
EOF

  mkdir -p /etc/apt/preferences.d

  cat > "$PIN_FILE" <<EOF
Package: *
Pin: origin deb.debian.org
Pin-Priority: 900

Package: *
Pin: origin security.debian.org
Pin-Priority: 900

Package: *
Pin: origin repo.iut.ac.ir
Pin-Priority: 100

Package: *
Pin: origin mirror.arvancloud.ir
Pin-Priority: 100
EOF

# ==============================================================================
# Ubuntu Configuration
# ==============================================================================
elif [[ "$OS_ID" == "ubuntu" ]]; then

  case "$OS_VER" in
    22.04) CODENAME="jammy" ;;
    24.04) CODENAME="noble" ;;
    *) die "Unsupported Ubuntu version: $OS_VER" ;;
  esac

  cat > "$MAIN_LIST" <<EOF
deb https://archive.ubuntu.com/ubuntu $CODENAME main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu $CODENAME-updates main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu $CODENAME-security main restricted universe multiverse
EOF

  cat > "$IR_LIST" <<EOF
deb http://repo.iut.ac.ir/ubuntu $CODENAME main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu $CODENAME-security main restricted universe multiverse
deb http://mirror.arvancloud.ir/ubuntu $CODENAME universe
EOF

  mkdir -p /etc/apt/preferences.d

  cat > "$PIN_FILE" <<EOF
Package: *
Pin: origin archive.ubuntu.com
Pin-Priority: 900

Package: *
Pin: origin security.ubuntu.com
Pin-Priority: 900

Package: *
Pin: origin repo.iut.ac.ir
Pin-Priority: 100

Package: *
Pin: origin mirror.arvancloud.ir
Pin-Priority: 100
EOF

else
  die "Unsupported OS: $OS_ID"
fi

rept "Repository configuration applied"
rept "APT pinning rules applied"

# ==============================================================================
# Refresh & Update
# ==============================================================================
info "Refreshing CA certificates..."

apt-get clean
apt-get install --reinstall -y ca-certificates >/dev/null
update-ca-certificates >/dev/null

rept "CA certificates refreshed"

info "Updating package index..."

apt-get update || die "APT update failed"

rept "APT update completed"

# ==============================================================================
# Final Summary
# ==============================================================================
info "══════════════════════════════════════════════"
rept "OS       : $PRETTY"
rept "Primary  : Official repositories"
rept "Fallback : Mirror repositories (IR)"
info "══════════════════════════════════════════════"

info "APT verification (policy bash):"
apt-cache policy bash | sed -n '1,15p'
