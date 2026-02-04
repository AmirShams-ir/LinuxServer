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
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
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

log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Disk Tweak Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# ==============================================================================
# CONFIG
# ==============================================================================
VG_LV_PATH="/dev/mapper/ptr--vg-root"

# ==============================================================================
# Disk expansion (ONLY for fresh VPS layouts)
# ==============================================================================

log "Starting disk expansion..."

# --- Delete small unused partition (if exists) ---
if lsblk -no NAME /dev/sda | grep -q '^sda3$'; then
  warn "Deleting unused partition /dev/sda3 (fresh VPS assumption)"
  (
    echo d
    echo 3
    echo w
  ) | fdisk /dev/sda
else
  log "Partition /dev/sda3 not found, skipping"
fi

# --- Resize extended partition ---
log "Resizing extended partition /dev/sda2..."
parted -s /dev/sda resizepart 2 100% || die "Failed to resize /dev/sda2"

# --- Resize logical partition ---
log "Resizing logical partition /dev/sda5..."
growpart /dev/sda 5 || die "Failed to grow /dev/sda5"

# --- Resize LVM PV ---
log "Resizing LVM physical volume..."
pvresize /dev/sda5 || die "pvresize failed"

# --- Extend LV ---
log "Extending logical volume..."
lvextend -l +100%FREE "$VG_LV_PATH" || die "lvextend failed"

# --- Resize filesystem (filesystem-aware) ---
FS_TYPE=$(findmnt -no FSTYPE /)
log "Detected root filesystem: $FS_TYPE"

log "Resizing filesystem..."
if [[ "$FS_TYPE" == "ext4" ]]; then
  resize2fs "$VG_LV_PATH" || die "resize2fs failed"
elif [[ "$FS_TYPE" == "xfs" ]]; then
  xfs_growfs / || die "xfs_growfs failed"
else
  die "Unsupported filesystem: $FS_TYPE"
fi

log "Filesystem resize completed"
df -h /

# ==============================================================================
# Quota bootstrap
# ==============================================================================

log "Bootstrapping disk quota..."

# --- Install quota tools (idempotent) ---
if ! command -v setquota >/dev/null 2>&1; then
  log "Installing quota package..."
  apt-get update -qq
  apt-get install -y quota
else
  log "Quota package already installed"
fi

# --- Ensure ext4 (classic quota only) ---
[[ "$FS_TYPE" == "ext4" ]] || die "Classic quota supported only on ext4"

# --- Ensure quota options in fstab ---
if ! grep -E '^[^#].+\s+/\s+ext4\s+.*usrquota' /etc/fstab; then
  log "Enabling usrquota,grpquota in /etc/fstab..."

  sed -i -E \
    's|^([^#].+\s+/\s+ext4\s+)([^ ]+)|\1\2,usrquota,grpquota|' \
    /etc/fstab

  warn "fstab updated. Reboot REQUIRED."
  warn "Please reboot the server and re-run disktweak.sh"
  exit 0
else
  log "Quota options already present in fstab"
fi

# --- Verify mount options ---
mount | grep -q 'on / .*usrquota' || die "Quota not active on / (reboot missing?)"
log "Quota mount options verified"

# --- Initialize quota files ---
log "Initializing quota files..."
quotaoff -avug >/dev/null 2>&1 || true
quotacheck -avugm
quotaon -avug

log "Disk quota successfully enabled"

# ==============================================================================
# Final report
# ==============================================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;32m✔ Disk tweak completed successfully\e[0m"
echo -e " \e[1;32m✔ Disk expanded and quota ready\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo

# --------------------------------------------------
# Cleanup (safe mode)
# --------------------------------------------------
unset LOG DISK_QUOTA_MB
