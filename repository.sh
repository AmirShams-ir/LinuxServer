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

set -euo pipefail

# --------------------------------------------------
# Logging
# --------------------------------------------------
LOG="/var/log/server-repo.log"
if touch "$LOG" &>/dev/null; then
  exec > >(tee -a "$LOG") 2>&1
  echo "[*] Logging enabled: $LOG"
fi

echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Repo Script Started\e[0m"
echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"

# --------------------------------------------------
# Root / sudo handling
# --------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo bash "$0" "$@"
  else
    echo "ERROR: Root privileges required."
    exit 1
  fi
fi

# --------------------------------------------------
# OS detection
# --------------------------------------------------
source /etc/os-release

OS_ID="$ID"
OS_VER="$VERSION_ID"
PRETTY="$PRETTY_NAME"

MAIN_LIST="/etc/apt/sources.list"
IR_LIST="/etc/apt/sources.list.d/ir-mirror.list"
PIN_FILE="/etc/apt/preferences.d/99-apt-priority"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cp -a "$MAIN_LIST" "${MAIN_LIST}.bak.${TIMESTAMP}"

echo "[*] Detected OS: $PRETTY"

# --------------------------------------------------
# Debian
# --------------------------------------------------
if [[ "$OS_ID" == "debian" ]]; then
  case "$OS_VER" in
    11) CODENAME="bullseye" ;;
    12) CODENAME="bookworm" ;;
    *) echo "Unsupported Debian version"; exit 1 ;;
  esac

  cat > "$MAIN_LIST" <<EOF
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${CODENAME}-security main contrib non-free non-free-firmware
EOF

  cat > "$IR_LIST" <<EOF
deb http://repo.iut.ac.ir/debian $CODENAME main contrib non-free non-free-firmware
EOF

# --------------------------------------------------
# Ubuntu
# --------------------------------------------------
elif [[ "$OS_ID" == "ubuntu" ]]; then
  case "$OS_VER" in
    22.04) CODENAME="jammy" ;;
    24.04) CODENAME="noble" ;;
    *) echo "Unsupported Ubuntu version"; exit 1 ;;
  esac

  cat > "$MAIN_LIST" <<EOF
deb http://archive.ubuntu.com/ubuntu $CODENAME main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-security main restricted universe multiverse
EOF

  cat > "$IR_LIST" <<EOF
deb http://repo.iut.ac.ir/ubuntu $CODENAME main restricted universe multiverse
EOF

else
  echo "Unsupported OS"
  exit 1
fi

# --------------------------------------------------
# APT pinning (Official > Iranian)
# --------------------------------------------------
cat > "$PIN_FILE" <<EOF
Package: *
Pin: origin archive.ubuntu.com
Pin-Priority: 900

Package: *
Pin: origin deb.debian.org
Pin-Priority: 900

Package: *
Pin: origin security.ubuntu.com
Pin-Priority: 900

Package: *
Pin: origin security.debian.org
Pin-Priority: 900

Package: *
Pin: origin repo.iut.ac.ir
Pin-Priority: 100
EOF

# --------------------------------------------------
# Refresh CA & APT
# --------------------------------------------------
apt clean
apt install --reinstall -y ca-certificates >/dev/null
update-ca-certificates >/dev/null

apt update

echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;33mAPT repository configured successfully\e[0m"
echo -e "\e[1;33mOS : $PRETTY\e[0m"
echo -e "\e[1;33mPrimary : Official repositories\e[0m"
echo -e "\e[1;33mFallback: repo.iut.ac.ir\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"

echo
echo -e "\e[1;36mVerification (apt policy bash):\e[0m"
apt policy bash | sed -n '1,12p'
