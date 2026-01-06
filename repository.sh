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
    echo "Re-running script with sudo..."
    exec sudo bash "$0" "$@"
  else
    echo "Error: Root privileges required."
    exit 1
  fi
fi

# --------------------------------------------------
# OS validation
# --------------------------------------------------
if ! grep -Eqi '^(ID=(ubuntu|debian)|ID_LIKE=.*(debian|ubuntu))' /etc/os-release; then
  echo "ERROR: Debian/Ubuntu only."
  exit 1
fi
#!/usr/bin/env bash
set -euo pipefail

### ---------- Root check ----------
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

### ---------- Variables ----------
DEBIAN_CODENAME="bookworm"
MAIN_LIST="/etc/apt/sources.list"
IR_LIST="/etc/apt/sources.list.d/ir-mirror.list"
PIN_FILE="/etc/apt/preferences.d/99-debian-mirror-priority"

OFFICIAL_MIRROR="deb http://deb.debian.org/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware"
OFFICIAL_UPDATES="deb http://deb.debian.org/debian ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware"
OFFICIAL_SECURITY="deb http://security.debian.org/debian-security ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware"

IR_MIRROR="deb http://repo.iut.ac.ir/debian ${DEBIAN_CODENAME} main contrib non-free non-free-firmware"

### ---------- Backup ----------
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cp -a ${MAIN_LIST} ${MAIN_LIST}.bak.${TIMESTAMP}

### ---------- Configure official repositories ----------
cat > ${MAIN_LIST} <<EOF
# Official Debian repositories
${OFFICIAL_MIRROR}
${OFFICIAL_UPDATES}
${OFFICIAL_SECURITY}
EOF

echo "[OK] Official Debian repositories configured."

### ---------- Configure Iranian fallback mirror ----------
cat > ${IR_LIST} <<EOF
# Iranian fallback mirror (low priority)
${IR_MIRROR}
EOF

echo "[OK] Iranian fallback mirror added."

### ---------- APT pinning ----------
cat > ${PIN_FILE} <<EOF
Package: *
Pin: origin deb.debian.org
Pin-Priority: 900

Package: *
Pin: origin security.debian.org
Pin-Priority: 900

Package: *
Pin: origin repo.iut.ac.ir
Pin-Priority: 100
EOF

echo "[OK] APT pinning rules applied."

### ---------- Refresh CA & APT ----------
apt clean
apt install --reinstall -y ca-certificates >/dev/null
update-ca-certificates >/dev/null

echo "[OK] CA certificates refreshed."

### ---------- Update & verify ----------
apt update

echo
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e "\e[1;33mAPT mirror configuration completed successfully\e[0m"
echo -e "\e[1;33mPrimary : deb.debian.org\e[0m"
echo -e "\e[1;33mFallback: repo.iut.ac.ir\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"
echo
echo -e "\e[1;36mVerification (apt policy bash):\e[0m"
apt policy bash | sed -n '1,12p'
