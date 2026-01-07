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
LOG="/var/log/server-host.log"
if touch "$LOG" &>/dev/null; then
  exec > >(tee -a "$LOG") 2>&1
  echo "[*] Logging enabled: $LOG"
fi

echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Hosting Setup Script Started\e[0m"
echo -e "\e[1;33m══════════════════════════════════════════════════\e[0m"

# --------------------------------------------------
# Root / sudo handling
# --------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo bash "$0" "$@"
  else
    echo "ERROR: Root privileges required."
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

export DEBIAN_FRONTEND=noninteractive

# ==================================================
# HELPERS
# ==================================================
log()  { echo -e "\e[32m[✔] $1\e[0m"; }
warn() { echo -e "\e[33m[!] $1\e[0m"; }
die()  { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

#!/usr/bin/env bash
set -euo pipefail

PHP_VERSION="8.2"
BASE_DIR="/var/www"
LOG="/var/log/create-host.log"

exec >> "$LOG" 2>&1

log() { echo -e "\e[32m[✔] $1\e[0m"; }
die() { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root"

echo "=== CREATE NEW HOST ==="

read -rp "Domain (example.com): " DOMAIN
read -rp "Username (linux user): " USERNAME
read -rsp "Password: " PASSWORD; echo
read -rp "Email: " EMAIL

[[ -z "$DOMAIN" || -z "$USERNAME" || -z "$PASSWORD" ]] && die "Missing input"

WEBROOT="$BASE_DIR/$DOMAIN"
POOL_NAME="${USERNAME}"
SOCKET="/run/php/php-fpm-${USERNAME}.sock"
DB_NAME="db_${USERNAME}"
DB_USER="u_${USERNAME}"
DB_PASS=$(openssl rand -base64 16)

# ==================================================
# USER
# ==================================================
if id "$USERNAME" &>/dev/null; then
  die "User already exists"
fi

useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# ==================================================
# DIRECTORIES
# ==================================================
mkdir -p "$WEBROOT"/{public_html,logs,tmp}
chown -R "$USERNAME:$USERNAME" "$WEBROOT"
chmod 750 "$WEBROOT"

cat > "$WEBROOT/public_html/index.php" <<EOF
<?php
echo "Host $DOMAIN is ready ✅";
EOF

chown "$USERNAME:$USERNAME" "$WEBROOT/public_html/index.php"

# ==================================================
# PHP-FPM POOL (ISOLATED)
# ==================================================
cat > /etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf <<EOF
[$POOL_NAME]
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

# ==================================================
# DATABASE
# ==================================================
mysql <<MYSQL
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL

# ==================================================
# NGINX VHOST
# ==================================================
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

# ==================================================
# SSL
# ==================================================
certbot --nginx \
  -d "$DOMAIN" -d "www.$DOMAIN" \
  --agree-tos -m "$EMAIL" --redirect --non-interactive

# ==================================================
# REPORT
# ==================================================
cat <<EOF

=====================================
 HOST CREATED SUCCESSFULLY 🎉
=====================================
Domain     : $DOMAIN
User       : $USERNAME
Web Root   : $WEBROOT
DB Name    : $DB_NAME
DB User    : $DB_USER
DB Pass    : $DB_PASS
PHP Socket : $SOCKET
=====================================

EOF