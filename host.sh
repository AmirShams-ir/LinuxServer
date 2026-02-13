#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Mini WHM-style hosting manager for Debian/Ubuntu VPS.
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
    exec sudo --preserve-env=PATH bash "$0" "$@"
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

pause() { read -rp "Press ENTER to continue..."; }

# ==============================================================================
# Globals
# ==============================================================================
BASE_DIR="/var/www"
SUSPEND_ROOT="/var/www/_suspended"
PHP_VERSION=""
PHP_FPM_SERVICE=""

# ==============================================================================
# Service Detection
# ==============================================================================
detect_services() {

  info "Detecting required services..."

  command -v php >/dev/null || die "PHP not installed"
  PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

  PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"

  systemctl list-unit-files | grep -q "^${PHP_FPM_SERVICE}.service" \
    || die "PHP-FPM service not installed"

  systemctl is-active --quiet "$PHP_FPM_SERVICE" \
    || die "PHP-FPM not running"

  command -v mariadb >/dev/null || die "MariaDB not installed"
  systemctl is-active --quiet mariadb || die "MariaDB not running"

  rept "PHP $PHP_VERSION detected"
  rept "PHP-FPM ($PHP_FPM_SERVICE) running"
  rept "MariaDB running"
}

# ==============================================================================
# Auto Install
# ==============================================================================
auto_install() {

  info "Installing hosting requisites..."

  apt-get update -y

  apt-get install -y \
    nginx mariadb-server mariadb-client \
    php php-fpm php-cli php-mysql php-curl php-gd php-intl php-mbstring php-zip php-xml php-opcache \
    certbot python3-certbot-nginx \
    quota quotatool \
    curl wget unzip zip ca-certificates gnupg openssl bc \
    || die "Package installation failed"

  rept "All requisites installed"
  pause
}

# ==============================================================================
# Create Host
# ==============================================================================
create_host() {

  detect_services

  info "Creating hosting account..."

  read -rp "Domain: " DOMAIN
  read -rp "Username: " USERNAME
  read -rsp "Password: " PASSWORD; echo
  read -rp "Admin Email: " EMAIL

  [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Invalid domain"
  [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{2,15}$ ]] || die "Invalid username"

  WEBROOT="$BASE_DIR/$DOMAIN"
  SOCKET="/run/php/php-fpm-$USERNAME.sock"

  id "$USERNAME" &>/dev/null && die "User already exists"
  [[ -d "$WEBROOT" ]] && die "Domain directory already exists"

  useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd

  mkdir -p "$WEBROOT/public_html"
  chown -R "$USERNAME:$USERNAME" "$WEBROOT"

  echo "<?php phpinfo();" > "$WEBROOT/public_html/index.php"

  cat > "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf" <<EOF
[$USERNAME]
user = $USERNAME
group = $USERNAME
listen = $SOCKET
pm = ondemand
pm.max_children = 5
EOF

  systemctl reload "$PHP_FPM_SERVICE"

  DB_NAME="db_$USERNAME"
  DB_USER="u_$USERNAME"
  DB_PASS=$(openssl rand -base64 16)

  mariadb <<EOF
CREATE DATABASE \`$DB_NAME\`;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

  cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
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

  ln -s "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"

  nginx -t || die "Nginx config test failed"
  systemctl reload nginx

  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
    --agree-tos -m "$EMAIL" --redirect --non-interactive \
    || warn "SSL issuance skipped"

  rept "Hosting account created successfully"
  pause
}

# ==============================================================================
# Suspend Host
# ==============================================================================
suspend_host() {

  info "Suspending hosting account..."

  read -rp "Username: " USERNAME

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
  [[ -n "$HOME_DIR" ]] || die "User not found"

  DOMAIN=$(basename "$HOME_DIR")

  mkdir -p "$SUSPEND_ROOT"
  echo "<h1>Account Suspended</h1>" > "$SUSPEND_ROOT/index.html"

  sed -i "s|root .*;|root $SUSPEND_ROOT;|" "/etc/nginx/sites-available/$DOMAIN"

  if [[ -f "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf" ]]; then
    mv "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf" \
       "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf.suspended"
  fi

  nginx -t || die "Nginx config test failed"
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  rept "Host suspended"
  pause
}

# ==============================================================================
# Unsuspend Host
# ==============================================================================
unsuspend_host() {

  info "Unsuspending hosting account..."

  read -rp "Username: " USERNAME

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
  [[ -n "$HOME_DIR" ]] || die "User not found"

  DOMAIN=$(basename "$HOME_DIR")

  sed -i "s|root .*;|root $HOME_DIR/public_html;|" \
    "/etc/nginx/sites-available/$DOMAIN"

  if [[ -f "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf.suspended" ]]; then
    mv "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf.suspended" \
       "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf"
  fi

  nginx -t || die "Nginx config test failed"
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  rept "Host unsuspended"
  pause
}

# ==============================================================================
# Delete Host
# ==============================================================================
delete_host() {

  info "Deleting hosting account..."

  read -rp "Username: " USERNAME
  read -rp "Type DEL to confirm: " CONFIRM
  [[ "$CONFIRM" == "DEL" ]] || die "Cancelled"

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
  [[ -n "$HOME_DIR" ]] || die "User not found"

  DOMAIN=$(basename "$HOME_DIR")

  rm -f "/etc/nginx/sites-enabled/$DOMAIN"
  rm -f "/etc/nginx/sites-available/$DOMAIN"
  rm -f "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf"*

  mariadb <<EOF
DROP DATABASE IF EXISTS db_$USERNAME;
DROP USER IF EXISTS 'u_$USERNAME'@'localhost';
FLUSH PRIVILEGES;
EOF

  userdel -r "$USERNAME" || true

  nginx -t || die "Nginx config test failed"
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  rept "Host deleted successfully"
  pause
}

# ==============================================================================
# Menu
# ==============================================================================
while true; do
  clear
  info "══════════════════════════════════════"
  info " Mini WHM – CLI"
  info "══════════════════════════════════════"
  info "1) Auto Install Requisites"
  info "2) Detect Services"
  info "3) Create Host"
  info "4) Delete Host"
  info "5) Suspend Host"
  info "6) Unsuspend Host"
  info "7) Exit"
  echo
  read -rp "Select option [1-7]: " C

  case "$C" in
    1) auto_install ;;
    2) detect_services; pause ;;
    3) create_host ;;
    4) delete_host ;;
    5) suspend_host ;;
    6) unsuspend_host ;;
    7) exit 0 ;;
    *) warn "Invalid choice"; sleep 1 ;;
  esac
done
