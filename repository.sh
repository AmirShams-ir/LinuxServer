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
LOG="/var/log/server-repository.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "[✔] Logging enabled: $LOG"

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Repository Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

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
    11)
      CODENAME="bullseye"
      COMPONENTS="main contrib non-free"
      ;;
    12)
      CODENAME="bookworm"
      COMPONENTS="main contrib non-free non-free-firmware"
      ;;
    *)
      echo "ERROR: Unsupported Debian version: $OS_VER"
      exit 1
      ;;
  esac

  echo "[*] Configuring Debian $OS_VER ($CODENAME)"

  cat > "$MAIN_LIST" <<EOF
# Debian official repositories
deb http://deb.debian.org/debian $CODENAME $COMPONENTS
deb http://deb.debian.org/debian $CODENAME-updates $COMPONENTS
deb http://security.debian.org/debian-security ${CODENAME}-security $COMPONENTS
EOF

  cat > "$IR_LIST" <<EOF
# Iranian fallback mirror
deb http://repo.iut.ac.ir/debian $CODENAME $COMPONENTS
deb http://repo.iut.ac.ir/debian $CODENAME-updates $COMPONENTS
deb http://mirror.arvancloud.ir/debian $CODENAME $COMPONENTS
deb http://mirror.arvancloud.ir/debian-security $CODENAME-security $COMPONENTS
EOF

# --------------------------------------------------
# Debian APT pinning (Official > Iranian)
# --------------------------------------------------
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

echo "[OK] APT pinning rules applied."

# --------------------------------------------------
# Ubuntu
# --------------------------------------------------
elif [[ "$OS_ID" == "ubuntu" ]]; then

  case "$OS_VER" in
    22.04)
      CODENAME="jammy"
      ;;
    24.04)
      CODENAME="noble"
      ;;
    *)
      echo "ERROR: Unsupported Ubuntu version: $OS_VER"
      exit 1
      ;;
  esac

  echo "[*] Configuring Ubuntu $OS_VER ($CODENAME)"

  cat > "$MAIN_LIST" <<EOF
# Ubuntu official repositories
deb http://archive.ubuntu.com/ubuntu $CODENAME main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-security main restricted universe multiverse
EOF

  cat > "$IR_LIST" <<EOF
# Iranian fallback mirror
deb http://repo.iut.ac.ir/ubuntu $CODENAME main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu $CODENAME-security main restricted universe multiverse
deb http://mirror.arvancloud.ir/ubuntu $CODENAME universe
EOF

# --------------------------------------------------
# Ubuntu APT pinning (Official > Iranian)
# --------------------------------------------------
cat > "$PIN_FILE" <<EOF
Package: *

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

echo "[OK] APT pinning rules applied."

else
  echo "ERROR: Unsupported OS: $OS_ID"
  exit 1
fi

# --------------------------------------------------
# Refresh CA & APT (script-safe)
# --------------------------------------------------
apt-get clean
apt-get install --reinstall -y ca-certificates >/dev/null
update-ca-certificates >/dev/null

echo "[OK] CA certificates refreshed."

# --------------------------------------------------
# Update & verify
# --------------------------------------------------
apt-get update

echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;33mAPT repository configuration completed\e[0m"
echo -e "\e[1;33mOS       : $PRETTY\e[0m"
echo -e "\e[1;33mPrimary  : Official repositories\e[0m"
echo -e "\e[1;33mFallback : repo.iut.ac.ir (IR)\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"

echo
echo -e "\e[1;36mVerification (apt policy bash):\e[0m"
apt-cache policy bash | sed -n '1,15p'
