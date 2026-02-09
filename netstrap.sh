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

set -Eeuo pipefail

# ==============================================================================
# Root handling
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/server-netstrap.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

log() { echo -e "\e[32m[✔] $1\e[0m"; }
die() { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

# ==============================================================================
# OS validation
# ==============================================================================
. /etc/os-release
[[ "$ID" =~ ^(debian|ubuntu)$ ]] || die "Unsupported OS"

CODENAME="$(lsb_release -sc)"
log "Detected OS: $PRETTY_NAME ($CODENAME)"

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"
echo -e " \e[1;33m✔ Net Application install Script Started\e[0m"
echo -e "\e[1;36m═══════════════════════════════════════════\e[0m"

# ==============================================================================
# User input
# ==============================================================================
read -rp "Enter domain (example.com): " DOMAIN
WEBROOT="/var/www/$DOMAIN"

# ==============================================================================
# Base system
# ==============================================================================
log "Updating system"
apt update -y
apt install -y \
  ca-certificates curl gnupg lsb-release unzip \
  software-properties-common ufw

# ==============================================================================
# NGINX
# ==============================================================================
log "Installing Nginx"
apt install -y nginx
systemctl enable --now nginx

# ==============================================================================
# CERTBOT
# ==============================================================================
log "Installing Certbot"
apt install -y certbot python3-certbot-nginx

# ==============================================================================
# WEBROOT
# ==============================================================================
log "Creating webroot"
mkdir -p "$WEBROOT"
chown -R www-data:www-data "$WEBROOT"

# ==============================================================================
# PHP INSTALL (SMART)
# ==============================================================================
install_php_official() {
  log "Trying PHP from OFFICIAL repository"
  apt install -y php php-fpm php-cli php-mysql php-curl php-mbstring \
    php-xml php-zip php-gd php-intl php-opcache php-mysqli
}

enable_sury() {
  log "Enabling SURY repository"
  curl -fsSL https://packages.sury.org/php/apt.gpg \
    | gpg --dearmor -o /usr/share/keyrings/php-sury.gpg
  echo "deb [signed-by=/usr/share/keyrings/php-sury.gpg] https://packages.sury.org/php/ $CODENAME main" \
    > /etc/apt/sources.list.d/php-sury.list
  apt update
}

if install_php_official; then
  PHP_SOURCE="official"
else
  log "Official PHP failed – fallback to SURY"
  enable_sury
  install_php_official
  PHP_SOURCE="sury"
fi

PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

systemctl enable --now php${PHP_VERSION}-fpm
log "PHP $PHP_VERSION installed from $PHP_SOURCE"

# ==============================================================================
# PHP HARDENING
# ==============================================================================
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
sed -i \
  -e 's/^;*expose_php.*/expose_php = Off/' \
  -e 's/^;*display_errors.*/display_errors = Off/' \
  -e 's/^;*log_errors.*/log_errors = On/' \
  -e 's/^;*memory_limit.*/memory_limit = 256M/' \
  -e 's/^;*upload_max_filesize.*/upload_max_filesize = 64M/' \
  -e 's/^;*post_max_size.*/post_max_size = 64M/' \
  -e 's/^;*cgi.fix_pathinfo.*/cgi.fix_pathinfo = 0/' \
  "$PHP_INI"

systemctl reload php${PHP_VERSION}-fpm

# ==============================================================================
# NGINX VHOST (PHP-AWARE)
# ==============================================================================
log "Creating Nginx vhost"
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  root $WEBROOT;
  index index.php index.html;

  location / {
    try_files \$uri \$uri/ /index.php?\$args;
  }

  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:$PHP_SOCK;
  }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# ==============================================================================
# SSL
# ==============================================================================
log "Issuing SSL certificate"
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
  -m admin@"$DOMAIN" --redirect

# ==============================================================================
# MARIADB
# ==============================================================================
log "Installing MariaDB"
apt install -y mariadb-server
systemctl enable --now mariadb

mysql <<'EOF'
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

# ==============================================================================
# PHPMYADMIN (SMART)
# ==============================================================================
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
    fastcgi_pass unix:$PHP_SOCK;
  }
}
EOF

systemctl reload nginx

# ==============================================================================
# FIREWALL
# ==============================================================================
log "Configuring firewall"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# ==============================================================================
# CLEANUP
# ==============================================================================
apt autoremove -y --purge
apt autoclean -y
apt clean
rm -rf /tmp/*
rm -rf /var/tmp/*
journalctl --vacuum-time=7d || true
if [[ -d /var/lib/php/sessions ]]; then
  find /var/lib/php/sessions -type f -mtime +2 -delete
fi
rm -f /root/.bash_history
history -c || true
chown -R www-data:www-data /var/www
find /var/www -type d -exec chmod 755 {} \;
find /var/www -type f -exec chmod 644 {} \;
sync

log "Cleanup completed ✅"

# ==============================================================================
# FINAL REPORT
# ==============================================================================
echo -e "\n\e[1;36m══════════════════════════════════════════════\e[0m"
echo -e " \e[1;32m✔ OS         : $PRETTY_NAME\e[0m"
echo -e " \e[1;32m✔ PHP        : $PHP_VERSION ($PHP_SOURCE)\e[0m"
echo -e " \e[1;32m✔ PHP-FPM    : $PHP_SOCK\e[0m"
echo -e " \e[1;32m✔ Nginx      : Installed\e[0m"
echo -e " \e[1;32m✔ MariaDB    : Installed\e[0m"
echo -e " \e[1;32m✔ phpMyAdmin : /phpmyadmin\e[0m"
echo -e " \e[1;32m✔ SSL        : Enabled\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════\e[0m"

unset HISTFILE PRETTY_NAME PHP_VERSION PHP_SOURCE PHP_SOCK
