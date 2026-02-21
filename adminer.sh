#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: 1 Click Hosting for fresh Debian/Ubuntu VPS.
# Author: Amir Shams
# GitHub: https://github.com/AmirShams-ir/LinuxServer
# License: See GitHub repository for license details.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Root
# ==============================================================================
if [[ $EUID -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi

info(){ printf "\e[34m%s\e[0m\n" "$*"; }
ok(){ printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn(){ printf "\e[33m[!] %s\e[0m\n" "$*"; }
die(){ printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }
has_systemd(){ [[ -d /run/systemd/system ]]; }

# ==============================================================================
# OS Validation
# ==============================================================================
source /etc/os-release || die "Cannot detect OS"

case "$ID" in
  debian) [[ "$VERSION_ID" == "12" || "$VERSION_ID" == "13" ]] || die "Unsupported Debian";;
  ubuntu) [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]] || die "Unsupported Ubuntu";;
  *) die "Unsupported OS";;
esac

ok "OS: $PRETTY_NAME"

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
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ CloudPanel Adminer Installer"
info "═══════════════════════════════════════════"

read -p "Enter Domain (example: db.example.com): " SITE

# ==============================================================================
# Auto detect CloudPanel webroot
# ==============================================================================
WEBROOT=$(find /home -type d -path "*/htdocs/$SITE" 2>/dev/null | head -n 1)

if [ -z "$WEBROOT" ]; then
    info "Domain not found inside CloudPanel structure."
    exit 1
fi

# If public folder exists use it
if [ -d "$WEBROOT/public" ]; then
    WEBROOT="$WEBROOT/public"
fi

ok "Detected Webroot: $WEBROOT"

cd "$WEBROOT" || exit 1

# ==============================================================================
# Install Adminer
# ==============================================================================
wget -q https://www.adminer.org/latest.php -O index.php

# Secure permissions
chown -R $(stat -c '%U:%G' "$WEBROOT") "$WEBROOT"
chmod 640 index.php

# Create login
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo
HASH=$(openssl passwd -apr1 "$PASSWORD")
echo "$USERNAME:$HASH" > "$WEBROOT/.htpasswd"

# Enable Basic Auth
cat > "$WEBROOT/.htaccess" <<EOF
AuthType Basic
AuthName "Database Login"
AuthUserFile $WEBROOT/.htpasswd
Require valid-user
EOF

# ==============================================================================
# Final Summery
# ==============================================================================
info "═══════════════════════════════════════════"
ok "Adminer Installed Successfully"
ok "Access: https://$SITE"
info "═══════════════════════════════════════════"
uset SITE
