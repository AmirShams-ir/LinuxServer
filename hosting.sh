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
QUOTA_READY=0

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

pause() {
  echo
  read -rp "Press ENTER to continue..."
}

# ==============================================================================
# Auto install prerequisites
# ==============================================================================
ensure_pkg() {
  dpkg -s "$1" &>/dev/null && return
  warn "Installing missing package: $1"
  apt-get install -y "$1"
}

auto_install() {
  title "🔧 Auto Install Requisites"

  apt-get update -y

  for p in \
    nginx \
    mariadb-server mariadb-client \
    php php-fpm php-cli php-mysql php-curl php-gd php-intl php-mbstring php-zip php-xml php-opcache \
    certbot python3-certbot-nginx \
    quota quotatool \
    curl wget unzip zip lsb-release ca-certificates gnupg openssl bc
  do
    ensure_pkg "$p"
  done

  ok "All requisites are installed"
  pause
}

# ==============================================================================
# Auto Enable Quota on / (SAFE with set -Eeuo pipefail)
# ==============================================================================
enable_quota() {

  QUOTA_READY=0
  title "🧠 Checking and enabling quota (safe mode)"

  # Detect filesystem
  if ! ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null); then
    warn "Cannot detect filesystem – skipping quota"
    return 0
  fi

  if [[ ! "$ROOT_FS" =~ ^(ext4|xfs)$ ]]; then
    warn "Filesystem $ROOT_FS does not support quota – skipping"
    return 0
  fi

  ok "Root filesystem: $ROOT_FS"

  # Enable quota flags in fstab if missing
  if ! grep -Eq '^[^#].+[[:space:]]/[[:space:]].*(usrquota|uquota)' /etc/fstab; then
    warn "Quota flags not found in /etc/fstab – enabling"

    cp /etc/fstab "/etc/fstab.bak.$(date +%F-%H%M%S)" || return 0

    sed -i '/[[:space:]]\/[[:space:]]/{
      s/defaults/defaults,usrquota,grpquota/
      t
      s/\(.*\)/\1,usrquota,grpquota/
    }' /etc/fstab || return 0

    mount -o remount / 2>/dev/null || {
      warn "Remount failed – reboot required"
      return 0
    }

    ok "Filesystem remounted with quota"
  fi

  # Initialize quota
  if ! quotacheck -cum / >/dev/null 2>&1; then
    warn "quotacheck failed – quota not usable on this system"
    return 0
  fi

  # Enable quota
  if ! quotaon / >/dev/null 2>&1; then
    warn "quotaon failed – quota not usable"
    return 0
  fi

  ok "Quota successfully enabled on /"
  QUOTA_READY=1
}

# ==============================================================================
# Detect services (SAFE with set -e)
# ==============================================================================
detect_services() {

  # ---------------- PHP ----------------
  if ! command -v php >/dev/null 2>&1; then
    die "PHP is not installed"
  fi

  PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
  ok "PHP detected: $PHP_VERSION"

  PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=running \
    | awk '/php.*fpm/ {print $1; exit}')

  if [[ -z "$PHP_FPM_SERVICE" ]]; then
    die "PHP-FPM service is not running"
  fi

  ok "PHP-FPM service: $PHP_FPM_SERVICE"

  # ---------------- MariaDB ----------------
  if ! command -v mariadb >/dev/null 2>&1; then
    die "MariaDB client is not installed"
  fi

  if ! systemctl is-active --quiet mariadb; then
    die "MariaDB service is not running"
  fi

  MARIADB_VERSION=$(mariadb --version | awk '{print $5}')
  ok "MariaDB detected: $MARIADB_VERSION"

  # ---------------- phpMyAdmin ----------------
  PHPMYADMIN_PATH=""

  for p in \
    /usr/share/phpmyadmin \
    /usr/share/phpMyAdmin \
    /var/www/phpmyadmin \
    /var/www/html/phpmyadmin
  do
    if [[ -d "$p" ]]; then
      PHPMYADMIN_PATH="$p"
      break
    fi
  done

  if [[ -z "$PHPMYADMIN_PATH" ]]; then
    die "phpMyAdmin is not installed"
  fi

  ok "phpMyAdmin detected at: $PHPMYADMIN_PATH"
}

# ==============================================================================
# CREATE HOST
# ==============================================================================
create_host() {
  
title "🚀 Create Hosting Account"

 read -rp "$(echo -e "\e[36m➜ Domain:\e[0m ")" DOMAIN
 read -rp "$(echo -e "\e[36m➜ Username:\e[0m ")" USERNAME
 read -rsp "$(echo -e "\e[36m➜ Password:\e[0m ")" PASSWORD
 echo
 read -rp "$(echo -e "\e[36m➜ Admin Email (SSL):\e[0m ")" EMAIL
 read -rp "$(echo -e "\e[36m➜ Disk quota (MB, e.g. 1024):\e[0m ")" QUOTA_MB

  [[ -z "$DOMAIN" || -z "$USERNAME" || -z "$PASSWORD" ]] && die "Missing input"

  BASE_DIR="/var/www"
  WEBROOT="$BASE_DIR/$DOMAIN"
  SOCKET="/run/php/php-fpm-$USERNAME.sock"

  id "$USERNAME" &>/dev/null && die "User already exists"

  useradd -m -d "$WEBROOT" -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  ok "System user created"

  enable_quota
  
# Setquota
if [[ "$QUOTA_READY" -eq 1 ]]; then
  if setquota -u "$USERNAME" $((QUOTA_MB*1024)) $((QUOTA_MB*1024)) 0 0 / 2>/dev/null; then
    ok "Disk quota set to ${QUOTA_MB}MB"
  else
    warn "Quota enabled but failed to apply for user"
  fi
else
  warn "Quota not available – host created without disk limit"
fi

  mkdir -p "$WEBROOT"/{public_html,logs,tmp}
  chown -R "$USERNAME:$USERNAME" "$WEBROOT"
  echo "<?php phpinfo();" > "$WEBROOT/public_html/index.php"

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

  title "🎛 Hosting Created Successfully"
  echo " Domain : $DOMAIN"
  echo " User   : $USERNAME"
  echo " Quota  : ${QUOTA_MB}MB"
  echo " DB     : $DB_NAME"
  echo " DB Pass: $DB_PASS"

  pause
}

# ==============================================================================
# DELETE HOST
# ==============================================================================
delete_host() {
  detect_services
  title "🧹 Delete Hosting Account"

  read -rp "$(echo -e "\e[36m➜ Username:\e[0m ")" USERNAME
  [[ -z "$USERNAME" ]] && die "Username required"

  read -rp "$(echo -e "\e[36m➜ Type DEL to confirm:\e[0m ")" CONFIRM
  [[ "$CONFIRM" != "DEL" ]] && die "Cancelled"

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6 || true)
  DOMAIN=$(basename "$HOME_DIR")

  quotaon -p / &>/dev/null && setquota -u "$USERNAME" 0 0 0 0 / || true

  rm -f /etc/php/*/fpm/pool.d/$USERNAME.conf
  rm -f /etc/nginx/sites-enabled/$DOMAIN
  rm -f /etc/nginx/sites-available/$DOMAIN

  mariadb <<EOF
DROP DATABASE IF EXISTS db_$USERNAME;
DROP USER IF EXISTS 'u_$USERNAME'@'localhost';
FLUSH PRIVILEGES;
EOF

  userdel -r "$USERNAME" &>/dev/null || true

  systemctl reload nginx
  systemctl reload "$PHP_FPM_SERVICE"

  ok "Hosting account $USERNAME deleted completely"
  pause
}

# ==============================================================================
# MAIN MENU
# ==============================================================================
while true; do
  clear
  echo -e "${B}${C}══════════════════════════════════════${X}"
  echo -e "${B}${C} 🚀 Mini WHM – Modern CLI${X}"
  echo -e "${B}${C}══════════════════════════════════════${X}"
  echo
  echo -e " ${G}1${X}) Install Requisites"
  echo -e " ${G}4${X}) Detect Services"
  echo -e " ${G}2${X}) Create Host"
  echo -e " ${G}3${X}) Delete Host"
  echo -e " ${G}4${X}) Exit Script"
  echo

  read -rp "Select an option [1-5]: " CHOICE

  case "$CHOICE" in
    1) auto_install ;;
    2) detect_services ;;
    3) create_host ;;
    4) delete_host ;;
    5) clear; exit 0 ;;
    *) warn "Invalid option"; sleep 1 ;;
  esac
done
