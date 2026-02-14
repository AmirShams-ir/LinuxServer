#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Host manager (Mini WHM) for Debian/Ubuntu VPS environments.
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
  exec sudo bash "$0" "$@"
fi

# ==============================================================================
# OS Validation
# ==============================================================================
source /etc/os-release
[[ "${ID}" == "debian" || "${ID}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* ]] \
  || { echo "Debian/Ubuntu only."; exit 1; }

# ==============================================================================
# Logging
# ==============================================================================
LOG="/var/log/miniwhm.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2> >(tee -a "$LOG" >&2)

# ==============================================================================
# Helpers
# ==============================================================================
info() { printf "\e[34m%s\e[0m\n" "$*"; }
ok()   { printf "\e[32m[✔] %s\e[0m\n" "$*"; }
warn() { printf "\e[33m[!] %s\e[0m\n" "$*"; }
die()  { printf "\e[31m[✖] %s\e[0m\n" "$*"; exit 1; }
pause(){ read -rp "Press ENTER to continue..."; }

# ==============================================================================
# Globals
# ==============================================================================
BASE_DIR="/var/www"
SUSPEND_ROOT="/var/www/_suspended"
REGISTRY="/var/lib/miniwhm/accounts.db"
mkdir -p "$(dirname "$REGISTRY")"
touch "$REGISTRY"

PHP_VERSION=""
PHP_FPM_SERVICE=""

# ==============================================================================
# Runtime Init
# ==============================================================================
init_runtime() {

  [[ -n "${PHP_VERSION:-}" && -n "${PHP_FPM_SERVICE:-}" ]] && return

  command -v php >/dev/null || die "PHP not installed"
  PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

  PHP_FPM_SERVICE=$(systemctl list-unit-files --type=service \
      | awk '/php.*-fpm.service/ {print $1}')

  [[ -n "$PHP_FPM_SERVICE" ]] || die "PHP-FPM not installed"
  systemctl is-active --quiet "$PHP_FPM_SERVICE" || die "PHP-FPM not running"
  systemctl is-active --quiet mariadb || die "MariaDB not running"
}

# ==============================================================================
# Auto Install
# ==============================================================================
auto_install() {

  info "Installing hosting stack..."
  apt-get update -y
  apt-get install -y \
    nginx mariadb-server \
    php php-fpm php-cli php-mysql php-curl php-gd php-intl php-mbstring php-zip php-xml \
    certbot python3-certbot-nginx \
    curl unzip openssl bc \
    || die "Install failed"

  ok "Stack installed"
  pause
}

# ==============================================================================
# Create Host
# ==============================================================================
create_host() {

  init_runtime

  read -rp "Domain: " DOMAIN
  read -rp "Username: " USERNAME
  read -rsp "Password: " PASSWORD; echo
  read -rp "Admin Email: " EMAIL

  [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Invalid domain"
  [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{2,15}$ ]] || die "Invalid username"

  WEBROOT="$BASE_DIR/$DOMAIN"
  SOCKET="/run/php/php-fpm-$USERNAME.sock"

  id "$USERNAME" &>/dev/null && die "User exists"
  [[ -d "$WEBROOT" ]] && die "Domain exists"

  useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd

  mkdir -p "$WEBROOT/public_html"
  chown -R "$USERNAME:$USERNAME" "$WEBROOT"
  echo "<?php phpinfo();" > "$WEBROOT/public_html/index.php"

SOCKET="/run/php/php-fpm-$USERNAME.sock"

cat > "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf" <<EOF
[$USERNAME]
user = $USERNAME
group = $USERNAME

listen = $SOCKET
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
pm.max_requests = 500

chdir = /
security.limit_extensions = .php
EOF

  systemctl reload "$PHP_FPM_SERVICE"

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

  nginx -t || die "Nginx error"
  systemctl reload nginx

  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
    --agree-tos -m "$EMAIL" --redirect --non-interactive || warn "SSL skipped"

  echo "$USERNAME|$DOMAIN|$EMAIL|active" >> "$REGISTRY"

  ok "Hosting account created"
  pause
}

# ==============================================================================
# Suspend Host
# ==============================================================================
suspend_host() {

  init_runtime

  read -rp "Username: " USERNAME
  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6) || die "User not found"
  DOMAIN=$(basename "$HOME_DIR")

  mkdir -p "$SUSPEND_ROOT"
  echo "<h1>Account Suspended</h1>" > "$SUSPEND_ROOT/index.html"

  sed -i "s|root .*;|root $SUSPEND_ROOT;|" "/etc/nginx/sites-available/$DOMAIN"

  mv "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf" \
     "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf.suspended" 2>/dev/null || true

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"
  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"
  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|\0|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|\1|" "$REGISTRY"

  sed -i "s|^$USERNAME|\0|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|\0|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|^$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|$USERNAME|$USERNAME|" "$REGISTRY"

  sed -i "s|active$|suspended|" "$REGISTRY"

  nginx -t || die "Nginx error"
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  ok "Host suspended"
  pause
}

# ==============================================================================
# Unsuspend Host
# ==============================================================================
unsuspend_host() {

  init_runtime

  read -rp "Username: " USERNAME
  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6) || die "User not found"
  DOMAIN=$(basename "$HOME_DIR")

  sed -i "s|root .*;|root $HOME_DIR/public_html;|" \
    "/etc/nginx/sites-available/$DOMAIN"

  mv "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf.suspended" \
     "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf" 2>/dev/null || true

  sed -i "s|suspended$|active|" "$REGISTRY"

  nginx -t || die "Nginx error"
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  ok "Host unsuspended"
  pause
}

# ==============================================================================
# Delete Host
# ==============================================================================
delete_host() {

  init_runtime

  read -rp "Username: " USERNAME
  read -rp "Type DEL to confirm: " CONFIRM
  [[ "$CONFIRM" == "DEL" ]] || die "Cancelled"

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6) || die "User not found"
  DOMAIN=$(basename "$HOME_DIR")

  rm -f "/etc/nginx/sites-enabled/$DOMAIN"
  rm -f "/etc/nginx/sites-available/$DOMAIN"
  rm -f "/etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf"*

  userdel -r "$USERNAME" || true

  sed -i "\|^$USERNAME|d" "$REGISTRY"

  nginx -t || die "Nginx error"
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  ok "Host deleted"
  pause
}

# ==============================================================================
# List Accounts (With Quota)
# ==============================================================================
list_accounts() {

  info "Hosting Accounts"
  echo

  [[ ! -s "$REGISTRY" ]] && { warn "No accounts found"; pause; return; }

  printf "%-15s %-20s %-25s %-10s %-8s\n" \
    "USER" "DOMAIN" "STATUS" "USED(MB)" "USE%"

  printf "%-15s %-20s %-25s %-10s %-8s\n" \
    "----" "------" "------" "--------" "-----"

  while IFS='|' read -r U D E S; do

    USED="N/A"
    PERCENT="N/A"

    if command -v quota >/dev/null && [[ "$S" == "active" ]]; then

      Q=$(quota -u "$U" 2>/dev/null | awk 'NR==3')

      if [[ -n "$Q" ]]; then
        USED_MB=$(echo "$Q" | awk '{print int($2/1024)}')
        SOFT_MB=$(echo "$Q" | awk '{print int($3/1024)}')

        if [[ "$SOFT_MB" -gt 0 ]]; then
          PERCENT=$(( USED_MB * 100 / SOFT_MB ))
        else
          PERCENT="0"
        fi

        USED="$USED_MB"
        PERCENT="${PERCENT}%"
      fi
    fi

    printf "%-15s %-20s %-25s %-10s %-8s\n" \
      "$U" "$D" "$S" "$USED" "$PERCENT"

  done < "$REGISTRY"

  echo
  pause
}

# ==============================================================================
# Cleanup
# ==============================================================================
cleanup() {

info "Performing cleanup..."

  apt-get autoremove -y
  apt-get autoclean -y
  
  unset PHP_VERSION
  unset PHP_FPM_SERVICE

  ok "Cleanup completed"
  pause
  }

# ==============================================================================
# Quota Status
# ==============================================================================
quota_status() {

  info "Quota Status Report"
  echo

  command -v quota >/dev/null || {
    warn "Quota tools not installed"
    pause
    return
  }

  if [[ ! -s "$REGISTRY" ]]; then
    warn "No hosting accounts found"
    pause
    return
  fi

  printf "%-15s %-10s %-10s %-10s %-8s\n" \
    "USER" "USED(MB)" "SOFT(MB)" "HARD(MB)" "USE%"

  printf "%-15s %-10s %-10s %-10s %-8s\n" \
    "----" "--------" "--------" "--------" "-----"

  while IFS='|' read -r USERNAME DOMAIN EMAIL STATUS; do

    [[ "$STATUS" == "active" ]] || continue

    Q=$(quota -u "$USERNAME" 2>/dev/null | awk 'NR==3')

    if [[ -z "$Q" ]]; then
      printf "%-15s %-10s %-10s %-10s %-8s\n" \
        "$USERNAME" "N/A" "N/A" "N/A" "N/A"
      continue
    fi

    USED=$(echo "$Q" | awk '{print int($2/1024)}')
    SOFT=$(echo "$Q" | awk '{print int($3/1024)}')
    HARD=$(echo "$Q" | awk '{print int($4/1024)}')

    if [[ "$SOFT" -gt 0 ]]; then
      PERCENT=$(( USED * 100 / SOFT ))
    else
      PERCENT="0"
    fi

    printf "%-15s %-10s %-10s %-10s %-8s\n" \
      "$USERNAME" "$USED" "$SOFT" "$HARD" "$PERCENT%"

  done < "$REGISTRY"

  echo
  pause
}

# ==============================================================================
# Install WordPress
# ==============================================================================
install_wordpress() {

  init_runtime

  info "WordPress Installer"
  echo

  read -rp "Username: " USERNAME

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6) || die "User not found"
  DOMAIN=$(basename "$HOME_DIR")
  WEBROOT="$HOME_DIR/public_html"

  [[ -d "$WEBROOT" ]] || die "Webroot not found"

  read -rp "Admin Email: " EMAIL

  DB_NAME="wp_${USERNAME}"
  DB_USER="u_${USERNAME}"
  DB_PASS=$(openssl rand -base64 16 | tr -dc a-zA-Z0-9 | head -c 16)

  info "Creating database..."

  mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}' OR REPLACE;"
  mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"

  ok "Database ready"

  info "Downloading WordPress..."

  cd /tmp
  curl -s https://wordpress.org/latest.tar.gz -o wp.tar.gz
  tar -xzf wp.tar.gz

  rm -rf "$WEBROOT"/*
  mv wordpress/* "$WEBROOT"
  rm -rf wordpress wp.tar.gz

  chown -R "$USERNAME:$USERNAME" "$WEBROOT"

  cp "$WEBROOT/wp-config-sample.php" "$WEBROOT/wp-config.php"

  sed -i "s/database_name_here/${DB_NAME}/" "$WEBROOT/wp-config.php"
  sed -i "s/username_here/${DB_USER}/" "$WEBROOT/wp-config.php"
  sed -i "s/password_here/${DB_PASS}/" "$WEBROOT/wp-config.php"

  SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
  sed -i "/AUTH_KEY/d" "$WEBROOT/wp-config.php"
  echo "$SALT" >> "$WEBROOT/wp-config.php"

  ok "WordPress installed successfully"
  echo
  echo "🌍 URL: https://${DOMAIN}"
  echo "🗄 DB: ${DB_NAME}"
  echo "👤 DB User: ${DB_USER}"
  echo "🔐 DB Pass: ${DB_PASS}"
  echo

  pause
}

# ==============================================================================
# Menu
# ==============================================================================
while true; do
  clear
  info "══════════════════════════════════════════════"
  info "🌐 Mini WHM CLI"
  info "══════════════════════════════════════════════"
  info "1) Auto Install"
  info "2) Create Host"
  info "3) Delete Host"
  info "4) Suspend Host"
  info "5) Unsuspend Host"
  info "6) List Accounts"
  info "7) Install WordPress"
  info "8) Cleanup"
  info "9) Exit"
  echo
  read -rp "Select [1-9]: " C

  case "$C" in
    1) auto_install ;;
    2) create_host ;;
    3) delete_host ;;
    4) suspend_host ;;
    5) unsuspend_host ;;
    6) list_accounts ;;
    7) install_wordpress ;;
    8) cleanup ;;
    9) exit 0 ;;
    *) warn "Invalid choice"; sleep 1 ;;
  esac
done
