#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Net Application Bootstrap (Nginx + PHP + MariaDB + SSL)
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
    exec sudo -E bash "$0" "$@"
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

CODENAME="${VERSION_CODENAME:-$(lsb_release -sc 2>/dev/null || true)}"

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
info "✔ Net Application Bootstrap Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# User Input
# ==============================================================================
info "Collecting configuration input..."

read -rp "Enter domain (example.com): " DOMAIN
[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Invalid domain"

WEBROOT="/var/www/$DOMAIN"

rept "Input validated"

# ==============================================================================
# Base System Packages
# ==============================================================================
info "Installing base packages..."

apt-get update -y
apt-get install -y \
  ca-certificates curl gnupg lsb-release unzip \
  software-properties-common \
  nginx certbot python3-certbot-nginx \
  mariadb-server \
  || die "Base package installation failed"

systemctl enable --now nginx
systemctl enable --now mariadb

rept "Base packages installed"

# ==============================================================================
# PHP Installation (Official → SURY Fallback)
# ==============================================================================
info "Installing PHP..."

install_php() {
  apt-get install -y \
    php php-fpm php-cli php-mysql php-curl php-mbstring \
    php-xml php-zip php-gd php-intl php-opcache
}

if install_php; then
  PHP_SOURCE="official"
else
  warn "Official PHP failed, enabling SURY repository"

  curl -fsSL https://packages.sury.org/php/apt.gpg \
    | gpg --dearmor -o /usr/share/keyrings/php-sury.gpg

  echo "deb [signed-by=/usr/share/keyrings/php-sury.gpg] \
https://packages.sury.org/php/ $CODENAME main" \
    > /etc/apt/sources.list.d/php-sury.list

  apt-get update
  install_php || die "PHP installation failed"
  PHP_SOURCE="sury"
fi

PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

systemctl enable --now "php${PHP_VERSION}-fpm"

rept "PHP $PHP_VERSION installed from $PHP_SOURCE"

# ==============================================================================
# PHP Hardening
# ==============================================================================
info "Applying PHP hardening..."

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

systemctl reload "php${PHP_VERSION}-fpm"

rept "PHP hardened"

# ==============================================================================
# Nginx Virtual Host
# ==============================================================================
info "Configuring Nginx virtual host..."

[[ -f "/etc/nginx/sites-available/$DOMAIN" ]] && die "Vhost already exists"

mkdir -p "$WEBROOT"
chown -R www-data:www-data "$WEBROOT"

cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
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

ln -s "/etc/nginx/sites-available/$DOMAIN" \
      "/etc/nginx/sites-enabled/$DOMAIN"

rm -f /etc/nginx/sites-enabled/default

nginx -t || die "Nginx configuration test failed"
systemctl reload nginx

rept "Nginx virtual host configured"

# ==============================================================================
# SSL Certificate
# ==============================================================================
info "Issuing SSL certificate..."

if certbot --nginx -d "$DOMAIN" \
  --non-interactive --agree-tos \
  -m "admin@$DOMAIN" --redirect; then
  rept "SSL certificate installed"
else
  warn "SSL issuance failed"
fi

# ==============================================================================
# phpMyAdmin
# ==============================================================================
info "Installing phpMyAdmin..."

echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections

apt-get install -y phpmyadmin || warn "phpMyAdmin install failed"

ln -sf /usr/share/phpmyadmin /var/www/phpmyadmin

rept "phpMyAdmin configured"

# ==============================================================================
# Network Monitor
# ==============================================================================
info "Configuring vnStat..."

systemctl enable --now vnstat

rept "Network monitor enabled"

# ==============================================================================
# Cleanup
# ==============================================================================
info "Performing cleanup..."

apt-get autoremove -y
apt-get autoclean -y

chown -R www-data:www-data /var/www
find /var/www -type d -exec chmod 755 {} \;
find /var/www -type f -exec chmod 644 {} \;

rept "Cleanup completed"

# ==============================================================================
# Final Summary
# ==============================================================================
info "══════════════════════════════════════════════"
rept "OS         : $PRETTY_NAME"
rept "PHP        : $PHP_VERSION ($PHP_SOURCE)"
rept "Nginx      : Installed"
rept "MariaDB    : Installed"
rept "SSL        : Configured"
rept "phpMyAdmin : /phpmyadmin"
info "══════════════════════════════════════════════"

unset DOMAIN PHP_VERSION PHP_SOURCE PHP_SOCK WEBROOT
