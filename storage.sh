#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Smart disk auto-expansion and quota bootstrap for Debian/Ubuntu VPS.
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
info "✔ Disk Tweak Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Required Packages
# ==============================================================================
info "Verifying required disk tools..."

REQUIRED_PKGS=(parted cloud-guest-utils lvm2 quota)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || MISSING_PKGS+=("$pkg")
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
  info "Installing missing packages: ${MISSING_PKGS[*]}"
  apt-get update -qq
  apt-get install -y "${MISSING_PKGS[@]}" || die "Package installation failed"
else
  rept "All required packages already installed"
fi

rept "Required disk tools verified"

# ==============================================================================
# Disk Detection
# ==============================================================================
info "Detecting root disk layout..."

ROOT_SRC="$(findmnt -no SOURCE /)"
FS_TYPE="$(findmnt -no FSTYPE /)"

info "Root source     : $ROOT_SRC"
info "Filesystem type : $FS_TYPE"

rept "Disk layout detection completed"

# ==============================================================================
# Disk Expansion
# ==============================================================================
info "Starting disk expansion phase..."

# ----- LVM root -----
if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then

  PV_DEV="$(lsblk -no PKNAME "$(readlink -f "$ROOT_SRC")" | head -n1)"
  PV_DEV="/dev/$PV_DEV"

  if [[ -b "$PV_DEV" ]]; then
    pvresize "$PV_DEV" || die "pvresize failed"
    lvextend -l +100%FREE "$ROOT_SRC" || die "lvextend failed"

    if [[ "$FS_TYPE" == "ext4" ]]; then
      resize2fs "$ROOT_SRC" || die "resize2fs failed"
    elif [[ "$FS_TYPE" == "xfs" ]]; then
      xfs_growfs / || die "xfs_growfs failed"
    else
      warn "Unsupported filesystem for resize: $FS_TYPE"
    fi

    rept "LVM disk expansion completed"
  else
    warn "Could not detect physical volume device"
  fi

# ----- Direct partition (sd/vd/nvme) -----
elif [[ "$ROOT_SRC" =~ ^/dev/(sd|vd)[a-z][0-9]+$ || "$ROOT_SRC" =~ ^/dev/nvme[0-9]+n[0-9]+p[0-9]+$ ]]; then

  DISK_DEV="/dev/$(lsblk -no PKNAME "$ROOT_SRC")"
  PART_NUM="$(echo "$ROOT_SRC" | grep -o '[0-9]*$')"

  growpart "$DISK_DEV" "$PART_NUM" || warn "Partition already at maximum size"

  if [[ "$FS_TYPE" == "ext4" ]]; then
    resize2fs "$ROOT_SRC" || die "resize2fs failed"
  elif [[ "$FS_TYPE" == "xfs" ]]; then
    xfs_growfs / || die "xfs_growfs failed"
  else
    warn "Unsupported filesystem for resize: $FS_TYPE"
  fi

  rept "Direct partition expansion completed"

else
  warn "Unknown root layout ($ROOT_SRC). Skipping resize."
fi

rept "Disk expansion phase completed"
df -h /

# ==============================================================================
# Quota Bootstrap
# ==============================================================================
info "Starting quota bootstrap..."

[[ "$FS_TYPE" == "ext4" ]] || die "Classic quota supported only on ext4"

if ! grep -E '^[^#].+\s+/\s+ext4\s+.*usrquota' /etc/fstab; then

  sed -i -E \
    's|^([^#].+\s+/\s+ext4\s+)([^ ]+)|\1\2,usrquota,grpquota|' \
    /etc/fstab

  warn "fstab updated. Reboot REQUIRED."
  warn "Reboot and re-run disktweak.sh"
  exit 0
fi

mount | grep -q 'on / .*usrquota' || die "Quota not active (reboot missing?)"

quotaoff -avug >/dev/null 2>&1 || true
quotacheck -avugm || die "quotacheck failed"
quotaon -avug || die "quotaon failed"

rept "Disk quota successfully enabled"

# ==============================================================================
# Final Summary
# ==============================================================================
info "══════════════════════════════════════════════════"
rept "Disk tweak completed successfully"
rept "Disk expanded and quota ready"
info "══════════════════════════════════════════════════"

unset LOG ROOT_SRC FS_TYPE PV_DEV DISK_DEV PART_NUM
