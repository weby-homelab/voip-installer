#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resolve Project Root (Parent of 'tools' directory)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Navigate to Project Root to ensure paths are correct
cd "$PROJECT_ROOT" || { echo "Error: Could not find project root"; exit 1; }

if [ -z "$1" ]; then
  echo -e "${BLUE}VoIP Installer Release Manager${NC}"
  echo "Usage: ./tools/release.sh <new_version>"
  echo "Example: ./tools/release.sh 4.7.7"
  exit 1
fi

NEW_VER="$1"
CURRENT_VER=$(grep 'VERSION="' install.sh | cut -d'"' -f2)

echo -e "🚀 Updating version from ${GREEN}v${CURRENT_VER}${NC} to ${GREEN}v${NEW_VER}${NC}..."

# 1. Update install.sh
sed -i "s/VERSION=\"${CURRENT_VER}\"/VERSION=\"${NEW_VER}\"/". install.sh
echo "✅ Updated install.sh"

# 2. Update README files
# Update the main Version header (English, Russian, Ukrainian)
sed -i "s/Version:** \
vim${CURRENT_VER}\"/Version:** \
vim${NEW_VER}\"/". README.md
sed -i "s/Версия:** \
vim${CURRENT_VER}\"/Версия:** \
vim${NEW_VER}\"/". README_RUS.md
sed -i "s/Версія:** \
vim${CURRENT_VER}\"/Версія:** \
vim${NEW_VER}\"/". README_UKR.md

# Update references in text (e.g. "script v4.7.6")
sed -i "s/v${CURRENT_VER}/v${NEW_VER}/g" README.md
sed -i "s/v${CURRENT_VER}/v${NEW_VER}/g" README_RUS.md
sed -i "s/v${CURRENT_VER}/v${NEW_VER}/g" README_UKR.md

echo "✅ Updated README.md"
echo "✅ Updated README_RUS.md"
echo "✅ Updated README_UKR.md"

echo -e "\n🎉 Done! Ready to commit:"
echo -e "${BLUE}git add . && git commit -m \"feat: release v${NEW_VER}\" && git tag v${NEW_VER} && git push && git push --tags${NC}"