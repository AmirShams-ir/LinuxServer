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
LOG="/var/log/server-apps.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "[✔] Logging enabled: $LOG"

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Application install Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# ==================================================
# CONFIG
# ==================================================
read -rp "Enter PHP Version (e.g. 8.1): " PHP_VERSION
read -rp "Enter Domain (e.g. example.com): " DOMAIN
LOG="/var/log/apps-hosting.log"

exec > >(tee -a "$LOG") 2>&1

log() { echo -e "\e[32m[✔] $1\e[0m"; }
die() { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ==================================================
# BASE SYSTEM
# ==================================================
log "Updating system"
apt update -y

apt install -y \
  ca-certificates \
  apt-transport-https \
  lsb-release \
  gnupg2 \
  curl \
  unzip \
  software-properties-common

# ==================================================
# NGINX
# ==================================================
log "Installing Nginx"
apt install -y nginx
systemctl enable nginx
systemctl start nginx

# ==================================================
# CERTBOT
# ==================================================
log "Installing Certbot"
apt install -y certbot python3-certbot-nginx

# ==================================================
# NGINX VHOST + SSL
# ==================================================
WEBROOT="/var/www/$DOMAIN"

log "Creating web root"
mkdir -p "$WEBROOT"
chown -R www-data:www-data "$WEBROOT"

log "Creating Nginx vhost for $DOMAIN"
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    root $WEBROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

log "Enabling Nginx vhost"
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

log "Removing default Nginx site"
rm -f /etc/nginx/sites-enabled/default

log "Testing Nginx config"
nginx -t

log "Reloading Nginx"
systemctl reload nginx

# ==================================================
# SSL CERTIFICATE (Let's Encrypt)
# ==================================================
log "Issuing SSL certificate for $DOMAIN"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN --redirect

log "Reloading Nginx after SSL"
systemctl reload nginx

# ==================================================
# MARIADB
# ==================================================
log "Installing MariaDB"
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb

# ==================================================
# MARIADB HARDENING
# ==================================================
log "Hardening MariaDB"

mysql <<'EOF'
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
DROP USER IF EXISTS 'root'@'%';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

# ==================================================
# DETECT OS
# ==================================================
. /etc/os-release
CODENAME=$(lsb_release -sc)
log "Detected OS: $PRETTY_NAME ($CODENAME)"

# ==================================================
# SELECT PHP SOURCE
# ==================================================
if [[ "$ID" == "debian" && "$VERSION_ID" == "11" ]]; then
  PHP_SOURCE="sury"
elif [[ "$ID" == "debian" && "$VERSION_ID" == "12" ]]; then
  PHP_SOURCE="native"
elif [[ "$ID" == "ubuntu" && "$VERSION_ID" == "22.04" ]]; then
  PHP_SOURCE="sury"
elif [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]; then
  PHP_SOURCE="native"
else
  die "Unsupported OS version"
fi

log "Installing PHP $PHP_VERSION from $PHP_SOURCE"

# ==================================================
# ENABLE SURY REPO (Debian 11 / Ubuntu 22.04)
# ==================================================
if [[ "$PHP_SOURCE" == "sury" ]]; then
apt install -y ca-certificates curl gnupg lsb-release

curl -4fsSL https://packages.sury.org/php/apt.gpg \
  | gpg --dearmor -o /usr/share/keyrings/php-sury.gpg

echo "deb [signed-by=/usr/share/keyrings/php-sury.gpg] https://packages.sury.org/php/ bullseye main" \
  > /etc/apt/sources.list.d/php-sury.list

apt update

fi


# ==================================================
# INSTALL PHP
# ==================================================
apt install -y \
  php${PHP_VERSION} \
  php${PHP_VERSION}-fpm \
  php${PHP_VERSION}-cli \
  php${PHP_VERSION}-mysql \
  php${PHP_VERSION}-curl \
  php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-xml \
  php${PHP_VERSION}-zip \
  php${PHP_VERSION}-gd \
  php${PHP_VERSION}-intl \
  php${PHP_VERSION}-opcache \
  php${PHP_VERSION}-mysqli

systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm

# ==================================================
# PHP HARDENING
# ==================================================
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
log "Applying PHP hardening"

sed -i 's/^;*expose_php.*/expose_php = Off/' "$PHP_INI"
sed -i 's/^;*display_errors.*/display_errors = Off/' "$PHP_INI"
sed -i 's/^;*log_errors.*/log_errors = On/' "$PHP_INI"
sed -i 's/^;*memory_limit.*/memory_limit = 256M/' "$PHP_INI"
sed -i 's/^;*upload_max_filesize.*/upload_max_filesize = 64M/' "$PHP_INI"
sed -i 's/^;*post_max_size.*/post_max_size = 64M/' "$PHP_INI"
sed -i 's/^;*max_execution_time.*/max_execution_time = 60/' "$PHP_INI"
sed -i 's/^;*cgi.fix_pathinfo.*/cgi.fix_pathinfo = 0/' "$PHP_INI"

systemctl reload php${PHP_VERSION}-fpm

# ==================================================
# PHPMYADMIN
# ==================================================
log "Installing phpMyAdmin"

echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
apt install -y phpmyadmin

ln -sf /usr/share/phpmyadmin /var/www/phpmyadmin

cat > /etc/nginx/snippets/phpmyadmin.conf <<EOF
location /phpmyadmin {
    root /var/www;
    index index.php;
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }
}
EOF

# ==================================================
# FIREWALL
# ==================================================
log "Configuring firewall"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# ==================================================
# PHP REPORT
# ==================================================
echo
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;32m✔ PHP INSTALLATION COMPLETED 🎉\e[0m"
echo -e " \e[1;32m✔ OS        : $PRETTY_NAME\e[0m"
echo -e " \e[1;32m✔ PHP       : $PHP_VERSION\e[0m"
echo -e " \e[1;32m✔ Source    : $PHP_SOURCE\e[0m"
echo -e " \e[1;32m✔ FPM Sock  : /run/php/php${PHP_VERSION}-fpm.sock\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"

unset DOMAIN WEBROOT
unset PHP_INI PHP_SOURCE PHP_VERSION PRETTY_NAME CODENAME
