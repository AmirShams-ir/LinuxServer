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
LOG="/var/log/server-disk.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "[✔] Logging enabled: $LOG"

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Disk Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# ==============================================================================
# CONFIG
# ==============================================================================
DISK_QUOTA_MB=1024

exec > >(tee -a "$LOG") 2>&1

log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ------------------------------------------------------------------------------
# Delete small partition /dev/sda3 if it exists
# ------------------------------------------------------------------------------
if fdisk -l /dev/sda | grep -q "/dev/sda3"; then
  echo "Deleting small partition /dev/sda3..."
  (
    echo d
    echo 3
    echo w
  ) | fdisk /dev/sda || {
    echo "Failed to delete partition /dev/sda3!"
    exit 1
  }
else
  echo "Partition /dev/sda3 does not exist. Skipping deletion."
fi

# ------------------------------------------------------------------------------
# Resize extended partition /dev/sda2
# ------------------------------------------------------------------------------
echo "Resizing extended partition /dev/sda2..."
parted /dev/sda resizepart 2 100% || {
  echo "Failed to resize extended partition (sda2)!"
  exit 1
}
echo "✅ extended partition /dev/sda2"

# ------------------------------------------------------------------------------
# Resize logical partition /dev/sda5
# ------------------------------------------------------------------------------
echo "Resizing logical partition /dev/sda5..."
growpart /dev/sda 5 || {
  echo "Failed to resize logical partition (sda5)!"
  exit 1
}

# ------------------------------------------------------------------------------
# Resize LVM physical volume
# ------------------------------------------------------------------------------
echo "Resizing LVM physical volume..."
pvresize /dev/sda5 || {
  echo "Failed to resize LVM physical volume!"
  exit 1
}
echo "✅ Resize LVM physical volume"

# ------------------------------------------------------------------------------
# Extend logical volume
# ------------------------------------------------------------------------------
echo "Extending logical volume..."
lvextend -l +100%FREE /dev/mapper/ptr--vg-root || {
  echo "Failed to extend logical volume!"
  exit 1
}

# ------------------------------------------------------------------------------
# Resize filesystem
# ------------------------------------------------------------------------------
echo "Resizing filesystem..."
if mountpoint -q /; then
  resize2fs /dev/mapper/ptr--vg-root || {
    echo "Failed to resize ext4 filesystem!"
    exit 1
  }
else
  xfs_growfs / || {
    echo "Failed to resize XFS filesystem!"
    exit 1
  }
fi
echo "✅ filesystem Resize"
echo "********************"
# Show results
echo "✅ Disk expansion completed successfully!"
echo "New disk size:"
df -h

# ------------------------------------------------------------------------------
# Install quota tools (idempotent)
# ------------------------------------------------------------------------------
if ! command -v setquota >/dev/null 2>&1; then
  log "Installing quota package..."
  apt-get update -qq
  apt-get install -y quota
else
  log "Quota package already installed"
fi

# ------------------------------------------------------------------------------
# Detect root filesystem
# ------------------------------------------------------------------------------
ROOT_FS_TYPE=$(findmnt -no FSTYPE /)

if [[ "$ROOT_FS_TYPE" != "ext4" ]]; then
  die "Unsupported filesystem for classic quota: $ROOT_FS_TYPE"
fi

log "Root filesystem detected: ext4"

# ------------------------------------------------------------------------------
# Ensure quota options exist in /etc/fstab
# ------------------------------------------------------------------------------
if ! grep -E '^[^#].+\s+/\s+ext4\s+.*usrquota' /etc/fstab; then
  log "Enabling usrquota,grpquota on root filesystem in fstab..."

  sed -i -E \
    's|^([^#].+\s+/\s+ext4\s+)([^ ]+)|\1\2,usrquota,grpquota|' \
    /etc/fstab

  log "fstab updated – reboot REQUIRED"
  warn "Please reboot the server and re-run bootstrap.sh to finalize quota"
  exit 0
else
  log "Quota options already present in fstab"
fi

# ------------------------------------------------------------------------------
# Verify mount options
# ------------------------------------------------------------------------------
if ! mount | grep -q 'on / .*usrquota'; then
  die "Root filesystem is not mounted with quota options (reboot missing?)"
fi

log "Quota mount options verified"

# ------------------------------------------------------------------------------
# Initialize quota files (safe to re-run)
# ------------------------------------------------------------------------------
log "Initializing quota files..."

quotaoff -avug >/dev/null 2>&1 || true
quotacheck -avugm
quotaon -avug

log "Disk quota successfully enabled on /"

# --------------------------------------------------
# Final Report
# --------------------------------------------------
echo
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;32m✔ Bootstrap completed successfully\e[0m"
echo -e " \e[1;32m✔ System is clean, updated & production-ready\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo

# --------------------------------------------------
# Cleanup (safe mode)
# --------------------------------------------------
unset LOG DISK_QUOTA_MB
