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
[[ $EUID -eq 0 ]] || exec sudo -E bash "$0" "$@"

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
LOG="/var/log/server-host.log"
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
# Globals
# ==============================================================================
QUOTA_READY=0
BASE_DIR="/var/www"
SUSPEND_ROOT="/var/www/_suspended"

# ==============================================================================
# Colors & helpers
# ==============================================================================
B="\e[1m"; R="\e[31m"; G="\e[32m"; Y="\e[33m"; C="\e[36m"; X="\e[0m"
ok()    { echo -e "${G}✔${X} $*"; }
warn()  { echo -e "${Y}⚠${X} $*"; }
die()   { echo -e "${R}✖${X} $*"; exit 1; }
title() { echo -e "\n${B}${C}$*${X}"; }

pause() { echo; read -rp "Press ENTER to continue..."; }

# ==============================================================================
# Auto install requisites
# ==============================================================================
ensure_pkg() {
  dpkg -s "$1" &>/dev/null && return
  warn "Installing: $1"
  apt-get install -y "$1"
}

auto_install() {
  title "🔧 Auto Install Requisites"
  apt-get update -y

  for p in \
    nginx mariadb-server mariadb-client \
    php php-fpm php-cli php-mysql php-curl php-gd php-intl php-mbstring php-zip php-xml php-opcache \
    certbot python3-certbot-nginx \
    quota quotatool \
    curl wget unzip zip ca-certificates gnupg openssl bc
  do
    ensure_pkg "$p"
  done

  ok "All requisites installed"
  pause
}

# ==============================================================================
# Detect services
# ==============================================================================
detect_services() {

  command -v php >/dev/null || die "PHP not installed"
  PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

  PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=running \
    | awk '/php.*fpm/ {print $1; exit}')
  [[ -n "$PHP_FPM_SERVICE" ]] || die "PHP-FPM not running"

  command -v mariadb >/dev/null || die "MariaDB not installed"
  systemctl is-active --quiet mariadb || die "MariaDB not running"

  PHPMYADMIN=""
  for p in /usr/share/phpmyadmin /usr/share/phpMyAdmin; do
    [[ -d "$p" ]] && PHPMYADMIN="$p"
  done
  [[ -n "$PHPMYADMIN" ]] || die "phpMyAdmin not installed"

  ok "PHP $PHP_VERSION | $PHP_FPM_SERVICE"
  ok "MariaDB OK"
  ok "phpMyAdmin OK"
}

# ==============================================================================
# Enable quota (safe)
# ==============================================================================
enable_quota() {
  QUOTA_READY=0
  ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null || true)

  [[ "$ROOT_FS" =~ ^(ext4|xfs)$ ]] || {
    warn "Filesystem $ROOT_FS – quota skipped"
    return
  }

  if ! quotacheck -cum / &>/dev/null; then
    warn "Quota not usable on this VPS"
    return
  fi

  quotaon / &>/dev/null || return
  QUOTA_READY=1
  ok "Quota enabled"
}

# ==============================================================================
# Create Host
# ==============================================================================
create_host() {
  detect_services
  enable_quota

  title "🚀 Create Hosting Account"

  read -rp "➜ Domain: " DOMAIN
  read -rp "➜ Username: " USERNAME
  read -rsp "➜ Password: " PASSWORD; echo
  read -rp "➜ Admin Email: " EMAIL
  read -rp "➜ Disk quota (MB): " QUOTA_MB

  [[ "$DOMAIN" =~ \. ]] || die "Invalid domain"
  [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{2,15}$ ]] || die "Invalid username"
  [[ "$QUOTA_MB" =~ ^[0-9]+$ ]] || die "Invalid quota"

  WEBROOT="$BASE_DIR/$DOMAIN"
  SOCKET="/run/php/php-fpm-$USERNAME.sock"

  id "$USERNAME" &>/dev/null && die "User exists"

  useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  ok "User created"

  if [[ "$QUOTA_READY" -eq 1 ]]; then
    setquota -u "$USERNAME" $((QUOTA_MB*1024)) $((QUOTA_MB*1024)) 0 0 / 2>/dev/null \
      && ok "Quota applied" || warn "Quota failed"
  else
    warn "Quota unavailable – soft limit only"
  fi

  mkdir -p "$WEBROOT"/{public_html,logs,tmp}
  chown -R "$USERNAME:$USERNAME" "$WEBROOT"
  echo "<?php phpinfo();" > "$WEBROOT/public_html/index.php"

  cat > /etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf <<EOF
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

  cat > /etc/nginx/sites-available/$DOMAIN <<EOF
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

  ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
  nginx -t && systemctl reload nginx

  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
    --agree-tos -m "$EMAIL" --redirect --non-interactive

  ok "Hosting created"
  pause
}

# ==============================================================================
# Suspend / Unsuspend
# ==============================================================================
suspend_host() {
  title "⏸ Suspend Host"
  read -rp "➜ Username: " USERNAME
  HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
  DOMAIN=$(basename "$HOME")

  mkdir -p "$SUSPEND_ROOT"
  echo "<h1>Account Suspended</h1>" > "$SUSPEND_ROOT/index.html"

  sed -i "s|root .*;|root $SUSPEND_ROOT;|" /etc/nginx/sites-available/$DOMAIN
  mv /etc/php/*/fpm/pool.d/$USERNAME.conf /etc/php/*/fpm/pool.d/$USERNAME.conf.suspended

  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  ok "Host suspended"
  pause
}

unsuspend_host() {
  title "▶ Unsuspend Host"
  read -rp "➜ Username: " USERNAME
  HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
  DOMAIN=$(basename "$HOME")

  sed -i "s|root .*;|root $HOME/public_html;|" /etc/nginx/sites-available/$DOMAIN
  mv /etc/php/*/fpm/pool.d/$USERNAME.conf.suspended /etc/php/*/fpm/pool.d/$USERNAME.conf

  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  ok "Host unsuspended"
  pause
}

# ==============================================================================
# Delete Host
# ==============================================================================
delete_host() {
  title "🧹 Delete Host"
  read -rp "➜ Username: " USERNAME
  read -rp "➜ Type DEL to confirm: " CONFIRM
  [[ "$CONFIRM" == "DEL" ]] || die "Cancelled"

  HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
  DOMAIN=$(basename "$HOME")

  rm -f /etc/nginx/sites-{enabled,available}/$DOMAIN
  rm -f /etc/php/*/fpm/pool.d/$USERNAME.conf*

  mariadb <<EOF
DROP DATABASE IF EXISTS db_$USERNAME;
DROP USER IF EXISTS 'u_$USERNAME'@'localhost';
FLUSH PRIVILEGES;
EOF

  userdel -r "$USERNAME" || true
  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  ok "Host deleted"
  pause
}

# ==============================================================================
# MENU
# ==============================================================================
while true; do
  clear
  echo -e "${B}${C}══════════════════════════════════════${X}"
  echo -e "${B}${C} 🚀 Mini WHM – FINAL CLI${X}"
  echo -e "${B}${C}══════════════════════════════════════${X}"
  echo
  echo " 1) Auto Install Requisites"
  echo " 2) Detect Services"
  echo " 3) Create Host"
  echo " 4) Delete Host"
  echo " 5) Suspend Host"
  echo " 6) Unsuspend Host"
  echo " 7) Exit"
  echo
  read -rp "Select option [1-7]: " C

  case "$C" in
    1) auto_install ;;
    2) detect_services; pause ;;
    3) create_host ;;
    4) delete_host ;;
    5) suspend_host ;;
    6) unsuspend_host ;;
    7) clear; exit 0 ;;
    *) warn "Invalid choice"; sleep 1 ;;
  esac
done
