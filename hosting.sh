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
LOG="/var/log/server-hosting.log"
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
# Colors & helpers
# ==============================================================================
B="\e[1m"; R="\e[31m"; G="\e[32m"; Y="\e[33m"; C="\e[36m"; X="\e[0m"

ok()    { echo -e "${G}✔${X} $*"; }
warn()  { echo -e "${Y}⚠${X} $*"; }
die()   { echo -e "${R}✖${X} $*"; exit 1; }
title() { echo -e "\n${B}${C}$*${X}"; }

read_input() {
  echo -ne "${C}➜${X} $1: "
  read -r val
  echo "$val"
}

read_secret() {
  echo -ne "${C}➜${X} $1: "
  read -rs val; echo
  echo "$val"
}

# ==============================================================================
# Auto install prerequisites
# ==============================================================================
ensure_pkg() {
  dpkg -s "$1" &>/dev/null && return
  warn "Installing missing package: $1"
  apt-get install -y "$1"
}

bootstrap() {
  title "🔍 Checking prerequisites"
  apt-get update -y

  for p in nginx mariadb-server mariadb-client \
           php php-fpm php-cli php-mysql \
           certbot python3-certbot-nginx \
           quota quotatool curl openssl; do
    ensure_pkg "$p"
  done
}

# ==============================================================================
# Detect services
# ==============================================================================
detect_services() {
  PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null) \
    || die "PHP not installed"

  PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=running \
    | awk '/php.*fpm/ {print $1; exit}')

  [[ -n "$PHP_FPM_SERVICE" ]] || die "PHP-FPM not running"

  ok "PHP $PHP_VERSION detected"
  ok "PHP-FPM: $PHP_FPM_SERVICE"
}

# ==============================================================================
# CREATE HOST
# ==============================================================================
create_host() {
  title "🚀 Create Hosting Account"

  DOMAIN=$(read_input "Domain")
  USERNAME=$(read_input "Username")
  PASSWORD=$(read_secret "Password")
  EMAIL=$(read_input "Admin Email (SSL)")
  QUOTA_MB=$(read_input "Disk quota (MB, e.g. 1024)")

  [[ -z "$DOMAIN" || -z "$USERNAME" || -z "$PASSWORD" ]] && die "Missing input"

  BASE_DIR="/var/www"
  WEBROOT="$BASE_DIR/$DOMAIN"
  SOCKET="/run/php/php-fpm-$USERNAME.sock"

  id "$USERNAME" &>/dev/null && die "User already exists"

  # User
  useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  ok "System user created"

  # Quota (safe)
  if quotaon -p / &>/dev/null; then
    setquota -u "$USERNAME" $((QUOTA_MB*1024)) $((QUOTA_MB*1024)) 0 0 /
    ok "Disk quota set to ${QUOTA_MB}MB"
  else
    warn "Quota not enabled on /. Skipping quota."
  fi

  # Directories
  mkdir -p "$WEBROOT"/{public_html,logs,tmp}
  chown -R "$USERNAME:$USERNAME" "$WEBROOT"
  echo "<?php phpinfo();" > "$WEBROOT/public_html/index.php"

  # PHP-FPM pool
  cat > /etc/php/$PHP_VERSION/fpm/pool.d/$USERNAME.conf <<EOF
[$USERNAME]
user = $USERNAME
group = $USERNAME
listen = $SOCKET
listen.owner = $USERNAME
listen.group = www-data
pm = ondemand
pm.max_children = 5
EOF

  systemctl reload "$PHP_FPM_SERVICE"
  ok "PHP-FPM pool created"

  # Database
  DB_NAME="db_$USERNAME"
  DB_USER="u_$USERNAME"
  DB_PASS=$(openssl rand -base64 16)

  mariadb <<EOF
CREATE DATABASE \`$DB_NAME\`;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

  ok "Database created"

  # Nginx
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
  ok "Nginx vhost enabled"

  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
    --agree-tos -m "$EMAIL" --redirect --non-interactive

  title "🎛 Hosting Created"
  echo " Domain : $DOMAIN"
  echo " User   : $USERNAME"
  echo " Quota  : ${QUOTA_MB}MB"
  echo " DB     : $DB_NAME"
  echo " DB Pass: $DB_PASS"
}

# ==============================================================================
# CLEANUP / DESTROY HOST
# ==============================================================================
cleanup_host() {
  title "🧹 Destroy Hosting Account"

  USERNAME=$(read_input "Username to DELETE")
  [[ -z "$USERNAME" ]] && die "Username required"

  read -rp "Type DELETE to confirm: " CONFIRM
  [[ "$CONFIRM" != "DELETE" ]] && die "Cancelled"

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6 || true)
  DOMAIN=$(basename "$HOME_DIR")

  # Quota cleanup
  quotaon -p / &>/dev/null && setquota -u "$USERNAME" 0 0 0 0 / || true

  # PHP-FPM
  rm -f /etc/php/*/fpm/pool.d/$USERNAME.conf

  # Nginx
  rm -f /etc/nginx/sites-enabled/$DOMAIN
  rm -f /etc/nginx/sites-available/$DOMAIN

  # DB
  mariadb <<EOF
DROP DATABASE IF EXISTS db_$USERNAME;
DROP USER IF EXISTS 'u_$USERNAME'@'localhost';
FLUSH PRIVILEGES;
EOF

  # User + home
  userdel -r "$USERNAME" &>/dev/null || true

  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  title "💣 Account Destroyed Completely"
  echo " User   : $USERNAME"
  echo " Domain : $DOMAIN"
}

# ==============================================================================
# MAIN
# ==============================================================================
bootstrap
detect_services

case "${1:-}" in
  create)  create_host ;;
  cleanup) cleanup_host ;;
  *)
    echo "Usage:"
    echo "  $0 create   → Create hosting account"
    echo "  $0 cleanup  → Destroy hosting account"
    exit 1
    ;;
esac
