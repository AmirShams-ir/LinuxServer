#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# CONFIG
# ==================================================
PHP_VERSION="8.2"
LOG="/var/log/apps-hosting.log"

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
# DETECT OS
# ==================================================
. /etc/os-release
log "Detected OS: $PRETTY_NAME"

# ==================================================
# SELECT PHP VERSION
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
read -rp "Enter PHP Version (e.g. 8.1): " PHP_VERSION
log "Installing PHP on $ID $VERSION_ID $PHP_VERSION ($PHP_SOURCE)"

# ==================================================
# ENABLE SURY REPO (Debian 11 - Ubuntu 22.04)
# ==================================================
if [[ "$PHP_SOURCE" == "sury" ]]; then

  apt update
  apt install -y ca-certificates apt-transport-https curl gnupg lsb-release

  # Add Sury GPG key
  curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/php.gpg

  # Add Sury repository explicitly for bullseye
  echo "deb [signed-by=/usr/share/keyrings/php.gpg] https://packages.sury.org/php/ bullseye main" \
    > /etc/apt/sources.list.d/php.list

  # Pin Sury repository (CRITICAL)
  cat <<EOF > /etc/apt/preferences.d/php-sury
Package: *
Pin: origin packages.sury.org
Pin-Priority: 1001
EOF
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
    php${PHP_VERSION}-opcache

systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm

# ==================================================
# PHP HARDENING (SAFE & UNIVERSAL)
# ==================================================
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"

log "Applying PHP hardening"

sed -i 's/^expose_php.*/expose_php = Off/' $PHP_INI
sed -i 's/^display_errors.*/display_errors = Off/' $PHP_INI
sed -i 's/^log_errors.*/log_errors = On/' $PHP_INI
sed -i 's/^memory_limit.*/memory_limit = 256M/' $PHP_INI
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 64M/' $PHP_INI
sed -i 's/^post_max_size.*/post_max_size = 64M/' $PHP_INI
sed -i 's/^max_execution_time.*/max_execution_time = 60/' $PHP_INI
sed -i 's/^cgi.fix_pathinfo.*/cgi.fix_pathinfo = 0/' $PHP_INI

systemctl reload php${PHP_VERSION}-fpm

# ==================================================
# PHP Version REPORT
# ==================================================
cat <<EOF

========================================
 PHP INSTALLATION COMPLETED 🎉
========================================
OS            : $PRETTY_NAME
PHP Version   : $PHP_VERSION
Source        : $PHP_SOURCE
FPM Socket    : /run/php/php${PHP_VERSION}-fpm.sock
========================================

Use this in create-host.sh:
PHP_VERSION="$PHP_VERSION"

========================================
EOF

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
# FINAL REPORT
# ==================================================

echo
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo -e " \e[1;32m✔ Nginx        : Installed\e[0m"
echo -e " \e[1;32m✔ MariaDB      : Installed\e[0m"
echo -e " \e[1;32m✔ PHP-FPM      : $PHP_VERSION\e[0m"
echo -e " \e[1;32m✔ PHP-MyAdmin  : Ready\e[0m"
echo -e " \e[1;32m✔ Certbot      : Ready\e[0m"
echo -e " \e[1;32m✔ Firewall     : Enabled\e[0m"
echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
echo

# --------------------------------------------------
# Cleanup (safe mode)
# --------------------------------------------------
unset PHP_INI PHP_SOURCE PHP_VERSION PRETTY_NAME