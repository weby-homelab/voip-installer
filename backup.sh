#!/usr/bin/bash
set -Eeuo pipefail

PROJECT_DIR="/root/voip-server"
BACKUP_DIR="/root/voip-backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/voip_backup_$TIMESTAMP.tar.gz"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: Project directory $PROJECT_DIR not found."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "Backing up $PROJECT_DIR to $BACKUP_FILE..."

tar -czf "$BACKUP_FILE" -C "$(dirname "$PROJECT_DIR")" "$(basename "$PROJECT_DIR")"

echo "Backup created successfully:"
ls -lh "$BACKUP_FILE"
