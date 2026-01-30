#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="/root/voip-server"
BACKUP_DIR="/root/voip-backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/voip_backup_$TIMESTAMP.tar.gz"

# Extra system configs managed by installer
NFT_CONF="/etc/nftables.conf"
F2B_JAIL="/etc/fail2ban/jail.local"
F2B_FILTER="/etc/fail2ban/filter.d/asterisk-pjsip-security.conf"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: Project directory $PROJECT_DIR not found."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "Backing up $PROJECT_DIR and system configs..."

# Create a temporary list of files to backup
TMP_LIST=$(mktemp)
find "$PROJECT_DIR" -print > "$TMP_LIST"
[[ -f "$NFT_CONF" ]] && echo "$NFT_CONF" >> "$TMP_LIST"
[[ -f "$F2B_JAIL" ]] && echo "$F2B_JAIL" >> "$TMP_LIST"
[[ -f "$F2B_FILTER" ]] && echo "$F2B_FILTER" >> "$TMP_LIST"

# Tar using the list (using -P to allow absolute paths for system files)
tar -czf "$BACKUP_FILE" -P -T "$TMP_LIST"

rm -f "$TMP_LIST"

echo "Backup created successfully:"
ls -lh "$BACKUP_FILE"