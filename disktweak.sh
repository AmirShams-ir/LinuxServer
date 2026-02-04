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
# Required disk tools (idempotent)
# ==============================================================================
log "Checking required disk tools..."

REQUIRED_PKGS=(parted cloud-guest-utils lvm2)

for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    log "Installing $pkg..."
    apt-get update -qq
    apt-get install -y "$pkg"
  else
    log "$pkg already installed"
  fi
done

# ==============================================================================
# SMART DISK EXPANSION (AUTO-DETECT)
# ==============================================================================

log "Detecting root disk layout..."

ROOT_SRC=$(findmnt -no SOURCE /)
FS_TYPE=$(findmnt -no FSTYPE /)

log "Root source      : $ROOT_SRC"
log "Filesystem type : $FS_TYPE"

# ------------------------------------------------------------------------------
# Case 1: LVM-based root (most common on VPS)
# ------------------------------------------------------------------------------
if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then
  log "LVM-based root detected"

  # Detect physical volume backing root VG
  PV_DEV=$(pvs --noheadings -o pv_name 2>/dev/null | awk '{print $1}' | head -n1)

  if [[ -z "$PV_DEV" ]]; then
    warn "No LVM physical volume detected. Skipping disk resize."
  else
    log "Detected LVM PV: $PV_DEV"

    log "Resizing physical volume..."
    pvresize "$PV_DEV" || die "pvresize failed"

    log "Extending logical volume..."
    lvextend -l +100%FREE "$ROOT_SRC" || die "lvextend failed"

    log "Resizing filesystem..."
    if [[ "$FS_TYPE" == "ext4" ]]; then
      resize2fs "$ROOT_SRC" || die "resize2fs failed"
    elif [[ "$FS_TYPE" == "xfs" ]]; then
      xfs_growfs / || die "xfs_growfs failed"
    else
      warn "Unsupported filesystem for resize: $FS_TYPE"
    fi
  fi

# ------------------------------------------------------------------------------
# Case 2: Direct partition root (non-LVM)
# ------------------------------------------------------------------------------
elif [[ "$ROOT_SRC" =~ ^/dev/sd[a-z][0-9]+$ || "$ROOT_SRC" =~ ^/dev/vd[a-z][0-9]+$ ]]; then
  log "Direct partition root detected"

  DISK_DEV="/dev/$(lsblk -no PKNAME "$ROOT_SRC")"
  PART_NUM="$(echo "$ROOT_SRC" | grep -o '[0-9]*$')"

  log "Disk device : $DISK_DEV"
  log "Partition  : $PART_NUM"

  log "Growing partition..."
  growpart "$DISK_DEV" "$PART_NUM" || die "growpart failed"

  log "Resizing filesystem..."
  if [[ "$FS_TYPE" == "ext4" ]]; then
    resize2fs "$ROOT_SRC" || die "resize2fs failed"
  elif [[ "$FS_TYPE" == "xfs" ]]; then
    xfs_growfs / || die "xfs_growfs failed"
  else
    warn "Unsupported filesystem for resize: $FS_TYPE"
  fi

# ------------------------------------------------------------------------------
# Case 3: Unknown / unsupported layout
# ------------------------------------------------------------------------------
else
  warn "Unknown root layout ($ROOT_SRC). Skipping disk resize."
fi

log "Disk expansion phase completed"
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
