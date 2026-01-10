#!/usr/bin/bash
set -Eeuo pipefail

# Colors
c_reset='\033[0m'; c_red='\033[0;31m'; c_grn='\033[0;32m'; c_ylw='\033[0;33m'; c_blu='\033[0;34m'
log_i(){ echo -e "${c_blu}[INFO]${c_reset} $*"; }
log_ok(){ echo -e "${c_grn}[OK]${c_reset} $*"; }
log_w(){ echo -e "${c_ylw}[WARN]${c_reset} $*"; }
log_e(){ echo -e "${c_red}[ERR]${c_reset} $*" >&2; }

PROJECT_DIR="/root/voip-server"
NFT_TABLE="voip_firewall"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  log_e "Please run as root."
  exit 1
fi

echo -e "${c_red}WARNING: This will uninstall the VoIP Server and delete related configurations.${c_reset}"
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_i "Aborted."
  exit 0
fi

# 1. Stop and remove Docker container
log_i "Stopping Asterisk container..."
if docker ps -a --format '{{.Names}}' | grep -q "^asterisk-voip$"; then
  docker stop asterisk-voip || true
  docker rm asterisk-voip || true
  log_ok "Container removed."
else
  log_i "Container not found, skipping."
fi

# 2. Remove NFTables table
log_i "Cleaning up Firewall..."
if nft list tables | grep -q "$NFT_TABLE"; then
  nft delete table inet "$NFT_TABLE" || true
  log_ok "Firewall table deleted."
else
  log_i "Firewall table not found."
fi

# 3. Remove Fail2Ban config
log_i "Cleaning up Fail2Ban..."
rm -f /etc/fail2ban/filter.d/asterisk-pjsip-security.conf
# We need to act carefully with jail.local as it might have other jails
# For now, we assume we want to disable our jails.
if [[ -f /etc/fail2ban/jail.local ]]; then
  # Simple backup before sed
  cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak
  # Remove the blocks (complex with sed, maybe just warn user)
  log_w "Fail2Ban configuration file /etc/fail2ban/jail.local was NOT deleted to avoid breaking other services."
  log_w "Please remove [asterisk-pjsip] block manually if needed."
  systemctl restart fail2ban || true
fi

# 4. Remove Data Directory
read -p "Do you want to delete ALL data (configs, logs, certs) in $PROJECT_DIR? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  log_i "Removing $PROJECT_DIR..."
  rm -rf "$PROJECT_DIR"
  log_ok "Data directory deleted."
else
  log_i "Data directory KEPT at $PROJECT_DIR"
fi

# 5. Remove Logrotate
rm -f /etc/logrotate.d/asterisk-cdr

log_ok "Uninstallation complete."
