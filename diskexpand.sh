#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: This script performs mandatory base initialization on a fresh
#              Linux VPS. It prepares the system with safe defaults, essential
#              tools, and baseline optimizations before any role-specific
#              configuration (hosting, security, WordPress, etc.).
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
#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Mandatory base initialization for fresh Debian/Ubuntu VPS
# Author: BabyBoss
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# -----------------------------------------------------------------------------

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root!"
  exit 1
fi

# Delete small partition /dev/sda3 if it exists
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

# Resize extended partition /dev/sda2
echo "Resizing extended partition /dev/sda2..."
parted /dev/sda resizepart 2 100% || {
  echo "Failed to resize extended partition (sda2)!"
  exit 1
}
echo "✅ extended partition /dev/sda2"
# Resize logical partition /dev/sda5
echo "Resizing logical partition /dev/sda5..."
growpart /dev/sda 5 || {
  echo "Failed to resize logical partition (sda5)!"
  exit 1
}

# Resize LVM physical volume
echo "Resizing LVM physical volume..."
pvresize /dev/sda5 || {
  echo "Failed to resize LVM physical volume!"
  exit 1
}
echo "✅ Resize LVM physical volume"
# Extend logical volume
echo "Extending logical volume..."
lvextend -l +100%FREE /dev/mapper/ptr--vg-root || {
  echo "Failed to extend logical volume!"
  exit 1
}

# Resize filesystem
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