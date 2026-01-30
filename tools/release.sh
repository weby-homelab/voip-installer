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

# Get current version from source of truth (install.sh)
CURRENT_VER=$(grep 'VERSION="' install.sh | cut -d'"' -f2 | tr -d '\r\n')

if [ -z "$CURRENT_VER" ]; then
  echo "Error: Could not detect current version from install.sh"
  exit 1
fi

# Determine New Version
if [ -z "$1" ]; then
  NEW_VER="$CURRENT_VER"
  echo -e "${YELLOW}No new version specified. Syncing docs with current version: v${CURRENT_VER}${NC}"
else
  NEW_VER="$1"
fi

if [ "$NEW_VER" != "$CURRENT_VER" ]; then
  echo -e "🚀 Updating version from ${GREEN}v${CURRENT_VER}${NC} to ${GREEN}v${NEW_VER}${NC}..."
  
  # 1. Update install.sh ONLY if version changed
  perl -pi -e "s/VERSION=\"${CURRENT_VER}\"/VERSION=\"${NEW_VER}\"/g" install.sh
  echo "✅ Updated install.sh"
else
  echo -e "ℹ️  Version unchanged. Skipping install.sh update."
fi

# 2. Update README files
# Update the main Version header (English, Russian, Ukrainian)
perl -pi -e "s/Version:\*\* \`v${CURRENT_VER}\` /Version:\*\* \`v${NEW_VER}\`/g" README.md
perl -pi -e "s/Версия:\*\* \`v${CURRENT_VER}\` /Версия:\*\* \`v${NEW_VER}\`/g" README_RUS.md
perl -pi -e "s/Версія:\*\* \`v${CURRENT_VER}\` /Версія:\*\* \`v${NEW_VER}\`/g" README_UKR.md

# Update references in text (e.g. "script v4.7.6")
# Note: We made "Step 2" generic, so this mainly affects the intro or other specific refs.
perl -pi -e "s/v${CURRENT_VER}/v${NEW_VER}/g" README.md
perl -pi -e "s/v${CURRENT_VER}/v${NEW_VER}/g" README_RUS.md
perl -pi -e "s/v${CURRENT_VER}/v${NEW_VER}/g" README_UKR.md

echo "✅ Synced README.md"
echo "✅ Synced README_RUS.md"
echo "✅ Synced README_UKR.md"

if [ "$NEW_VER" != "$CURRENT_VER" ]; then
  echo -e "\n🎉 Done! Ready to commit:"
  echo -e "${BLUE}git add . && git commit -m \"feat: release v${NEW_VER}\" && git tag v${NEW_VER} && git push && git push --tags${NC}"
else
  echo -e "\n✅ Docs synced to v${CURRENT_VER}."
fi