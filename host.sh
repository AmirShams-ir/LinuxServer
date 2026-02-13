#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Mini WHM – Production Grade Edition
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
# List Accounts
# ==============================================================================
list_accounts() {

  info "Hosting Accounts"
  echo

  [[ ! -s "$REGISTRY" ]] && { warn "No accounts found"; pause; return; }

  printf "%-15s %-25s %-30s %-10s\n" "USER" "DOMAIN" "EMAIL" "STATUS"
  printf "%-15s %-25s %-30s %-10s\n" "----" "------" "-----" "------"

  while IFS='|' read -r U D E S; do
    printf "%-15s %-25s %-30s %-10s\n" "$U" "$D" "$E" "$S"
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
  info "7) Quota Status"
  info "8) Cleanups"
  info "9) Exit"
  echo
  read -rp "Select [1-7]: " C

  case "$C" in
    1) auto_install ;;
    2) create_host ;;
    3) delete_host ;;
    4) suspend_host ;;
    5) unsuspend_host ;;
    6) list_accounts ;;
    7) cleanup ;;
    8) quota_status ;;
    9) exit 0 ;;
    *) warn "Invalid choice"; sleep 1 ;;
  esac
done
