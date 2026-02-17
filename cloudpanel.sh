#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Install Cloud Panel a fresh Debian/Ubuntu VPS.
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

has_systemd() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Cloud Panel Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Install CloudPanel
# ==============================================================================
install_cloudpanel() {

  if systemctl list-units --full -all | grep -q clp-agent; then
    warn "CloudPanel already installed. Skipping."
    return
  fi

  info "Installing CloudPanel..."
  curl -fsSL https://installer.cloudpanel.io/ce/v2/install.sh -o /tmp/clp.sh \
    || die "Download failed"

  bash /tmp/clp.sh || die "CloudPanel install failed"
  rm -f /tmp/clp.sh

  sleep 5

  systemctl is-active --quiet clp-agent \
    && info "CloudPanel service running" \
    || die "CloudPanel service failed"
}

# ==============================================================================
# Optimize MariaDB for 1GB
# ==============================================================================
optimize_mariadb_1gb() {

  info "Optimizing MariaDB for 1GB..."

  CONF="/etc/mysql/mariadb.conf.d/99-1gb.cnf"

  cat > "$CONF" <<EOF
[mysqld]
innodb_buffer_pool_size=256M
innodb_log_file_size=64M
innodb_flush_method=O_DIRECT
max_connections=30
tmp_table_size=32M
max_heap_table_size=32M
thread_cache_size=8
table_open_cache=400
query_cache_type=0
query_cache_size=0
EOF

  systemctl restart mariadb
  info "MariaDB optimized."
}

# ==============================================================================
# Optimize PHP-FPM for 1GB
# ==============================================================================
optimize_phpfpm_1gb() {

  info "Optimizing PHP-FPM pools..."

  for ver in 8.1 8.2; do
    POOL_DIR="/etc/php/$ver/fpm/pool.d"
    [[ -d "$POOL_DIR" ]] || continue

    for pool in "$POOL_DIR"/*.conf; do
      sed -i "s/^pm.max_children.*/pm.max_children = 4/" "$pool" || true
      sed -i "s/^pm.start_servers.*/pm.start_servers = 2/" "$pool" || true
      sed -i "s/^pm.min_spare_servers.*/pm.min_spare_servers = 1/" "$pool" || true
      sed -i "s/^pm.max_spare_servers.*/pm.max_spare_servers = 2/" "$pool" || true
      sed -i "s/^pm.max_requests.*/pm.max_requests = 300/" "$pool" || true
    done

    systemctl restart php$ver-fpm
  done

  info "PHP-FPM optimized."
}

# ==============================================================================
# Enable & Optimize OPcache
# ==============================================================================
optimize_opcache() {

  info "Configuring OPcache..."

  for ver in 8.1 8.2; do
    OPCACHE_FILE="/etc/php/$ver/fpm/conf.d/99-opcache.ini"
    [[ -d "/etc/php/$ver" ]] || continue

    cat > "$OPCACHE_FILE" <<EOF
opcache.enable=1
opcache.memory_consumption=64
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.validate_timestamps=1
opcache.revalidate_freq=60
opcache.save_comments=1
EOF

    systemctl restart php$ver-fpm
  done

  info "OPcache configured."
}

# ==============================================================================
# Disable Redis (if exists)
# ==============================================================================
disable_redis() {

  if systemctl list-unit-files | grep -q redis; then
    warn "Disabling Redis (not required for this setup)..."
    systemctl stop redis-server || true
    systemctl disable redis-server || true
  fi
}

# ==============================================================================
# Execute
# ==============================================================================
install_cloudpanel
optimize_mariadb_1gb
optimize_phpfpm_1gb
optimize_opcache
disable_redis
final_message

# ==============================================================================
# Cleanup
# ==============================================================================

cleanup() {

  info "Running cleanup tasks..."

  # Remove temporary installer files
  rm -f /tmp/clp.sh 2>/dev/null || true

  # Clear apt cache safely
  apt autoremove -y >/dev/null 2>&1 || true
  apt autoclean -y >/dev/null 2>&1 || true

  # Clear journal logs older than 7 days (prevent log bloat on 1GB VPS)
  journalctl --vacuum-time=7d >/dev/null 2>&1 || true

  # Clear temporary directories
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

  # Reload systemd daemon (safe refresh)
  systemctl daemon-reload || true

  info "Cleanup completed."
}

# ==============================================================================
# Final Info
# ==============================================================================
final_message() {

  IP=$(hostname -I | awk '{print $1}')

  info "====================================================="
  info " CloudPanel Installed & Optimized for 1GB VPS"
  info " Access: https://$IP:8443"
  info " MariaDB tuned"
  info " PHP-FPM limited"
  info " OPcache enabled"
  info " Redis disabled"
  info "====================================================="
}
