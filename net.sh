#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# CONFIG
# ==================================================
PHP_VERSION="8.2"
LOG="/var/log/bootstrap-hosting.log"

exec > >(tee -a "$LOG") 2>&1

log() { echo -e "\e[32m[✔] $1\e[0m"; }
die() { echo -e "\e[31m[✖] $1\e[0m"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root"

export DEBIAN_FRONTEND=noninteractive

# ==================================================
# OS CHECK
# ==================================================
grep -Eq 'debian|ubuntu' /etc/os-release || die "Only Debian/Ubuntu supported"

# ==================================================
# BASE SYSTEM
# ==================================================
log "Updating system"
apt update -y
apt upgrade -y

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
# Mariadb-Server
# ==================================================
log "Installing Mariadb-Server"
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb

# ==================================================
# MARIADB HARDENING
# ==================================================
log "Hardening MariaDB (safe method)"

mysql <<'EOF'
-- Ensure root uses unix_socket authentication
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;

-- Remove anonymous users
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';

-- Disable remote root login
DROP USER IF EXISTS 'root'@'%';

-- Remove test database
DROP DATABASE IF EXISTS test;

FLUSH PRIVILEGES;
EOF

log "MariaDB hardened successfully"

# ==================================================
# PHP + PHP-FPM
# ==================================================
log "Installing PHP $PHP_VERSION"

if ! apt-cache show php${PHP_VERSION}-fpm &>/dev/null; then
  add-apt-repository -y ppa:ondrej/php
  apt update -y
fi

apt install -y \
  php${PHP_VERSION}-fpm \
  php${PHP_VERSION}-cli \
  php${PHP_VERSION}-mysql \
  php${PHP_VERSION}-curl \
  php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-xml \
  php${PHP_VERSION}-zip \
  php${PHP_VERSION}-gd \
  php${PHP_VERSION}-intl

systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm

# ==================================================
# PHP GLOBAL HARDENING
# ==================================================
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"

sed -i 's/^expose_php.*/expose_php = Off/' $PHP_INI
sed -i 's/^memory_limit.*/memory_limit = 256M/' $PHP_INI
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 64M/' $PHP_INI
sed -i 's/^post_max_size.*/post_max_size = 64M/' $PHP_INI
sed -i 's/^max_execution_time.*/max_execution_time = 60/' $PHP_INI

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
# CERTBOT
# ==================================================
log "Installing Certbot"
apt install -y certbot python3-certbot-nginx

# ==================================================
# FIREWALL
# ==================================================
log "Configuring UFW"

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# ==================================================
# SYSTEM TUNING (LIGHT)
# ==================================================
log "Applying system tuning"

sysctl -w net.core.somaxconn=1024
sysctl -w fs.file-max=100000

# ==================================================
# FINAL
# ==================================================
log "Bootstrap completed successfully 🎉"

cat <<EOF

========================================
 HOSTING ENVIRONMENT READY
========================================
Nginx        : Installed
MySQL        : Installed
PHP-FPM      : $PHP_VERSION
phpMyAdmin   : /phpmyadmin
Certbot      : Ready
Firewall     : Enabled
========================================

EOF
