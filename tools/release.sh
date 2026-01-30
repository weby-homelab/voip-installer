#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Resolve Project Root (Parent of 'tools' directory)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || { echo "Error: Could not find project root"; exit 1; }

# Get current version from source of truth (the VERSION="" line)
CURRENT_VER=$(grep 'VERSION="' install.sh | cut -d'"' -f2 | tr -d '\r\n')

if [ -z "$CURRENT_VER" ]; then
  echo "Error: Could not detect current version from install.sh"
  exit 1
fi

# Determine New Version
if [ -z "$1" ]; then
  NEW_VER="$CURRENT_VER"
  echo -e "${YELLOW}No new version specified. Syncing headers/docs with current version: v${CURRENT_VER}${NC}"
else
  NEW_VER="$1"
fi

echo -e "🚀 Syncing/Updating version to ${GREEN}v${NEW_VER}${NC}..."

# 1. Update install.sh (Aggressive sync of all version mentions)
perl -pi -e "s/VERSION=\"[0-9.]*\"/VERSION=\"${NEW_VER}\"/g" install.sh
perl -pi -e "s/# VoIP Server Installer v[0-9.]*/# VoIP Server Installer v${NEW_VER}/g" install.sh
perl -pi -e "s/# Changes v[0-9.]*/# Changes v${NEW_VER}/g" install.sh
echo "✅ Synced install.sh"

# 2. Update README files (Sync Headers)
perl -pi -e "s/Version:\*\* \`v[0-9.]*\`/Version:\*\* \`v${NEW_VER}\`/g" README.md
perl -pi -e "s/Версия:\*\* \`v[0-9.]*\`/Версия:\*\* \`v${NEW_VER}\`/g" README_RUS.md
perl -pi -e "s/Версія:\*\* \`v[0-9.]*\`/Версія:\*\* \`v${NEW_VER}\`/g" README_UKR.md

# 3. Update Text References (v4.7.x)
# This is tricky because we don't want to replace historical changelogs.
# We'll only replace the previous version with the new one globally.
if [ "$NEW_VER" != "$CURRENT_VER" ]; then
  perl -pi -e "s/v${CURRENT_VER}/v${NEW_VER}/g" README.md
  perl -pi -e "s/v${CURRENT_VER}/v${NEW_VER}/g" README_RUS.md
  perl -pi -e "s/v${CURRENT_VER}/v${NEW_VER}/g" README_UKR.md
fi

echo "✅ Synced READMEs"

if [ "$NEW_VER" != "$CURRENT_VER" ]; then
  echo -e "\n🎉 Done! Ready to commit:"
  echo -e "${BLUE}git add . && git commit -m \"feat: release v${NEW_VER}\" && git tag v${NEW_VER} && git push && git push --tags${NC}"
else
  echo -e "\n✅ All files synced to v${NEW_VER}."
fi