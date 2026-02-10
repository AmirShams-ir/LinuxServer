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
LOG="/var/log/server-hosting.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "[✔] Logging enabled: $LOG"

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Hosting Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# ------------------------------------------------------------------------------
# Globals
# ------------------------------------------------------------------------------
BASE_DIR="/var/www"
DIALOG=dialog

log() { echo "[✔] $*"; }
die() { echo "[✖] $*" ; exit 1; }

# ------------------------------------------------------------------------------
# Detect services
# ------------------------------------------------------------------------------
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null) \
  || die "PHP not installed"

PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=running \
  | awk '/php.*fpm/ {print $1; exit}')

[[ -n "$PHP_FPM_SERVICE" ]] || die "PHP-FPM not running"

# ------------------------------------------------------------------------------
# CREATE HOST
# ------------------------------------------------------------------------------
create_host() {

  DOMAIN=$($DIALOG --inputbox "Domain name" 8 40 3>&1 1>&2 2>&3)
  USERNAME=$($DIALOG --inputbox "Username" 8 40 3>&1 1>&2 2>&3)
  PASSWORD=$($DIALOG --passwordbox "Password" 8 40 3>&1 1>&2 2>&3)
  EMAIL=$($DIALOG --inputbox "Admin Email (SSL)" 8 40 3>&1 1>&2 2>&3)
  QUOTA_MB=$($DIALOG --inputbox "Disk Quota (MB)" 8 40 "1024" 3>&1 1>&2 2>&3)

  [[ -z "$DOMAIN" || -z "$USERNAME" || -z "$PASSWORD" ]] && return

  id "$USERNAME" &>/dev/null && {
    $DIALOG --msgbox "User already exists!" 6 40
    return
  }

  WEBROOT="$BASE_DIR/$DOMAIN"
  SOCKET="/run/php/php-fpm-$USERNAME.sock"
  DB_NAME="db_$USERNAME"
  DB_USER="u_$USERNAME"
  DB_PASS=$(openssl rand -base64 16)

  # User
  useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd

  # Quota
  setquota -u "$USERNAME" $((QUOTA_MB*1024)) $((QUOTA_MB*1024)) 0 0 /

  # Dirs
  mkdir -p "$WEBROOT"/{public_html,logs,tmp}
  chown -R "$USERNAME:$USERNAME" "$WEBROOT"

  echo "<?php phpinfo();" > "$WEBROOT/public_html/index.php"

  # PHP-FPM
  cat > /etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf <<EOF
[$USERNAME]
user = $USERNAME
group = $USERNAME
listen = $SOCKET
listen.owner = $USERNAME
listen.group = www-data
pm = ondemand
pm.max_children = 5
EOF

  systemctl reload "$PHP_FPM_SERVICE"

  # DB
  mariadb <<EOF
CREATE DATABASE \`$DB_NAME\`;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

  # Nginx
  cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
  listen 80;
  server_name $DOMAIN www.$DOMAIN;
  root $WEBROOT/public_html;
  index index.php index.html;
  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:$SOCKET;
  }
}
EOF

  ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
  nginx -t && systemctl reload nginx

  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
    --agree-tos -m "$EMAIL" --redirect --non-interactive

  $DIALOG --msgbox "Hosting created successfully 🎉

Domain: $DOMAIN
User: $USERNAME
Quota: ${QUOTA_MB}MB
DB Pass: $DB_PASS" 12 50
}

# ------------------------------------------------------------------------------
# DELETE HOST (FULL DESTROY)
# ------------------------------------------------------------------------------
delete_host() {

  USERNAME=$($DIALOG --inputbox "Username to DELETE" 8 40 3>&1 1>&2 2>&3)
  [[ -z "$USERNAME" ]] && return

  $DIALOG --yesno "⚠️ This will COMPLETELY remove user $USERNAME\n
Home, DB, Nginx, PHP-FPM\n\nAre you sure?" 12 50 || return

  DOMAIN=$(basename "$(getent passwd "$USERNAME" | cut -d: -f6)")

  rm -f /etc/nginx/sites-enabled/$DOMAIN
  rm -f /etc/nginx/sites-available/$DOMAIN
  rm -f /etc/php/*/fpm/pool.d/$USERNAME.conf

  mariadb <<EOF
DROP DATABASE IF EXISTS db_$USERNAME;
DROP USER IF EXISTS 'u_$USERNAME'@'localhost';
FLUSH PRIVILEGES;
EOF

  userdel -r "$USERNAME" || true
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  $DIALOG --msgbox "User $USERNAME removed completely 🧨" 8 40
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------
while true; do
  CHOICE=$($DIALOG --menu "Mini WHM" 15 50 4 \
    1 "Create Hosting" \
    2 "Delete Hosting" \
    3 "Exit" \
    3>&1 1>&2 2>&3)

  case "$CHOICE" in
    1) create_host ;;
    2) delete_host ;;
    3|*) clear; exit ;;
  esac
done
