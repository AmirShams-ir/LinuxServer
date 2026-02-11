#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Smart disk auto-expansion and quota bootstrap for Debian/Ubuntu VPS.
#
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
#
# License: See GitHub repository for license details.
#
# Disclaimer: This script is provided for educational and informational
#             purposes only. Use it responsibly and in compliance with all
#             applicable laws and regulations.
#
# Note: SAFE, IDEMPOTENT, and NON-DESTRUCTIVE.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Root handling
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
# OS validation
# ==============================================================================
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
else
  printf "ERROR: Cannot detect OS.\n"
  exit 1
fi

if [[ "${ID}" != "debian" && "${ID}" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then
  printf "ERROR: Debian/Ubuntu only.\n"
  exit 1
fi

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
# Helper functions
# ==============================================================================
info() { printf "\e[34m%s\e[0m\n" "$*"; }
rept() { printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn() { printf "\e[33m[!] %s\e[0m\n" "$*"; }
die()  { printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Disk Tweak Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Required tools
# ==============================================================================
info "Checking required disk tools..."

REQUIRED_PKGS=(parted cloud-guest-utils lvm2 quota)

for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    info "Installing $pkg..."
    apt-get update -qq
    apt-get install -y "$pkg"
  else
    rept "$pkg already installed"
  fi
done

# ==============================================================================
# Disk detection
# ==============================================================================
info "Detecting root disk layout..."

ROOT_SRC="$(findmnt -no SOURCE /)"
FS_TYPE="$(findmnt -no FSTYPE /)"

info "Root source      : $ROOT_SRC"
info "Filesystem type  : $FS_TYPE"

# ==============================================================================
# Case 1: LVM root
# ==============================================================================
if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then

  info "LVM-based root detected"

  PV_DEV="$(pvs --noheadings -o pv_name 2>/dev/null | awk '{print $1}' | head -n1)"

  if [[ -z "$PV_DEV" ]]; then
    warn "No LVM physical volume detected. Skipping disk resize."
  else
    info "Resizing physical volume..."
    pvresize "$PV_DEV" || die "pvresize failed"

    info "Extending logical volume..."
    lvextend -l +100%FREE "$ROOT_SRC" || die "lvextend failed"

    info "Resizing filesystem..."
    if [[ "$FS_TYPE" == "ext4" ]]; then
      resize2fs "$ROOT_SRC" || die "resize2fs failed"
    elif [[ "$FS_TYPE" == "xfs" ]]; then
      xfs_growfs / || die "xfs_growfs failed"
    else
      warn "Unsupported filesystem for resize: $FS_TYPE"
    fi
  fi

# ==============================================================================
# Case 2: Direct partition
# ==============================================================================
elif [[ "$ROOT_SRC" =~ ^/dev/sd[a-z][0-9]+$ || "$ROOT_SRC" =~ ^/dev/vd[a-z][0-9]+$ ]]; then

  info "Direct partition root detected"

  DISK_DEV="/dev/$(lsblk -no PKNAME "$ROOT_SRC")"
  PART_NUM="$(echo "$ROOT_SRC" | grep -o '[0-9]*$')"

  info "Growing partition..."

  if growpart "$DISK_DEV" "$PART_NUM"; then
    rept "Partition grown successfully"
  else
    warn "Partition already at maximum size"
  fi

  info "Resizing filesystem..."

  if [[ "$FS_TYPE" == "ext4" ]]; then
    resize2fs "$ROOT_SRC" || die "resize2fs failed"
  elif [[ "$FS_TYPE" == "xfs" ]]; then
    xfs_growfs / || die "xfs_growfs failed"
  else
    warn "Unsupported filesystem for resize: $FS_TYPE"
  fi

else
  warn "Unknown root layout ($ROOT_SRC). Skipping disk resize."
fi

rept "Disk expansion phase completed"
df -h /

# ==============================================================================
# Quota bootstrap
# ==============================================================================
info "Bootstrapping disk quota..."

[[ "$FS_TYPE" == "ext4" ]] || die "Classic quota supported only on ext4"

if ! grep -E '^[^#].+\s+/\s+ext4\s+.*usrquota' /etc/fstab; then
  info "Enabling usrquota,grpquota in /etc/fstab..."

  sed -i -E \
    's|^([^#].+\s+/\s+ext4\s+)([^ ]+)|\1\2,usrquota,grpquota|' \
    /etc/fstab

  warn "fstab updated. Reboot REQUIRED."
  warn "Please reboot and re-run disktweak.sh"
  exit 0
fi

mount | grep -q 'on / .*usrquota' || die "Quota not active on / (reboot missing?)"
rept "Quota mount options verified"

info "Initializing quota files..."
quotaoff -avug >/dev/null 2>&1 || true
quotacheck -avugm
quotaon -avug

rept "Disk quota successfully enabled"

# ==============================================================================
# Final Report
# ==============================================================================
info "══════════════════════════════════════════════════"
info "Disk tweak completed successfully"
info "Disk expanded and quota ready"
info "══════════════════════════════════════════════════"

# ==============================================================================
# Cleanup
# ==============================================================================
unset LOG ROOT_SRC FS_TYPE PV_DEV DISK_DEV PART_NUM
