#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Description: Security hardening (UFW + Fail2Ban + Kernel tuning)
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

# ==============================================================================
# Banner
# ==============================================================================
info "═══════════════════════════════════════════"
info "✔ Security Setup Script Started"
info "═══════════════════════════════════════════"

# ==============================================================================
# Firewall (UFW)
# ==============================================================================
info "Installing and configuring UFW..."

apt-get update || die "APT update failed"
apt-get install -y ufw || die "UFW installation failed"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

ufw --force enable

rept "Firewall installed and configured and enabled"

# ==============================================================================
# Fail2Ban
# ==============================================================================
info "Installing and configuring Fail2Ban..."

apt-get update -y
apt-get install -y fail2ban apache2-utils || die "Fail2Ban installation failed"

mkdir -p /etc/fail2ban/filter.d

# ------------------------------------------------------------------------------
# phpMyAdmin filter
# ------------------------------------------------------------------------------
cat > /etc/fail2ban/filter.d/phpmyadmin.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(POST).*/index\.php.*" (200|302)
ignoreregex =
EOF

# ------------------------------------------------------------------------------
# Jail Configuration
# ------------------------------------------------------------------------------
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
backend  = systemd
usedns   = warn
banaction = iptables-multiport
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

# ----------------------
# SSH Protection
# ----------------------
[sshd]
enabled = true
port    = 22
logpath = /var/log/auth.log

# ----------------------
# Nginx Basic Auth
# ----------------------
[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 5

# ----------------------
# phpMyAdmin Login Protection
# ----------------------
[phpmyadmin]
enabled  = true
port     = http,https
filter   = phpmyadmin
logpath  = /var/log/nginx/access.log
maxretry = 5
EOF

systemctl enable fail2ban
systemctl restart fail2ban || die "Fail2Ban failed to start"

sleep 2
fail2ban-client status

rept "Fail2Ban fully hardened and active"

# ==============================================================================
# Kernel Hardening
# ==============================================================================
info "Applying kernel hardening..."

cat > /etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_fin_timeout = 15
EOF

sysctl --system >/dev/null || die "Sysctl reload failed"

rept "Kernel hardening applied"

# ==============================================================================
# Cleanup
# ==============================================================================
info "Performing cleanup..."

apt-get autoremove -y
apt-get autoclean -y

unset SSH_PORT

rept "Cleanup completed"

# ==============================================================================
# Final Summary
# ==============================================================================
info "══════════════════════════════════════════════"
rept "Firewall  : UFW enabled"
rept "Protection: Fail2Ban active"
rept "Kernel    : Hardened"
info "══════════════════════════════════════════════"
