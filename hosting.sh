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

# ==============================================================================
# CONFIG
# ==============================================================================
PHP_VERSION="8.3"
BASE_DIR="/var/www"
LOG="/var/log/create-host.log"
DISK_QUOTA_MB=1024

exec > >(tee -a "$LOG") 2>&1

log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ==============================================================================
# INPUT
# ==============================================================================
echo "=== CREATE NEW HOST ==="

read -rp "Domain (example.com): " DOMAIN
read -rp "Username: " USERNAME
read -rsp "Password: " PASSWORD; echo
read -rp "Email: " EMAIL

[[ -z "$DOMAIN" || -z "$USERNAME" || -z "$PASSWORD" ]] && die "Missing input"

WEBROOT="$BASE_DIR/$DOMAIN"
SOCKET="/run/php/php-fpm-${USERNAME}.sock"
DB_NAME="db_${USERNAME}"
DB_USER="u_${USERNAME}"
DB_PASS=$(openssl rand -base64 16)

# ==============================================================================
# USER
# ==============================================================================
id "$USERNAME" &>/dev/null && die "User already exists"

useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
log "User created"

# ==============================================================================
# QUOTA (1GB)
# ==============================================================================
setquota -u "$USERNAME" 1048576 1048576 0 0 /
log "Disk quota set for $USERNAME"

# ==============================================================================
# DIRECTORIES
# ==============================================================================
mkdir -p "$WEBROOT"/{public_html,logs,tmp}
chown -R "$USERNAME:$USERNAME" "$WEBROOT"
chmod 750 "$WEBROOT"

cat > "$WEBROOT/public_html/index.php" <<EOF
<?php
echo "🚀 $DOMAIN is ready";
EOF

chown "$USERNAME:$USERNAME" "$WEBROOT/public_html/index.php"

# ==============================================================================
# PHP-FPM POOL
# ==============================================================================
cat > /etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf <<EOF
[$USERNAME]
user = $USERNAME
group = $USERNAME

listen = $SOCKET
listen.owner = $USERNAME
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
pm.max_requests = 500

php_admin_value[open_basedir] = $WEBROOT:/tmp
php_admin_value[upload_tmp_dir] = $WEBROOT/tmp
php_admin_value[session.save_path] = $WEBROOT/tmp
EOF

systemctl reload php${PHP_VERSION}-fpm
log "PHP-FPM pool created"

# ==============================================================================
# DATABASE
# ==============================================================================
mysql <<MYSQL
CREATE DATABASE \`$DB_NAME\`;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL

log "Database created"

# ==============================================================================
# NGINX
# ==============================================================================
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    root $WEBROOT/public_html;
    index index.php index.html;

    access_log $WEBROOT/logs/access.log;
    error_log  $WEBROOT/logs/error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$SOCKET;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
nginx -t && systemctl reload nginx
log "Nginx vhost created"

# ==============================================================================
# SSL
# ==============================================================================
certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
  --agree-tos -m "$EMAIL" --redirect --non-interactive

log "SSL enabled"

# ==============================================================================
# WHM-LIKE REPORT
# ==============================================================================
cat <<EOF

══════════════════════════════════════
 🎛  HOST ACCOUNT SUMMARY (WHM STYLE)
══════════════════════════════════════
Domain        : $DOMAIN
System User   : $USERNAME
Home Dir      : $WEBROOT
Disk Quota    : ${DISK_QUOTA_MB} MB
PHP Version   : $PHP_VERSION
PHP Socket    : $SOCKET
Web Server    : Nginx
SSL           : Enabled (Let's Encrypt)
***************************************
MySQL Host    : localhost
Database Name : $DB_NAME
DB User       : $DB_USER
DB Password   : $DB_PASS
══════════════════════════════════════

EOF
