#!/bin/bash
set -e

# Get the directory of this script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_SCRIPT="$SCRIPT_DIR/../install.sh"

echo "Running syntax check on install.sh..."

if bash -n "$INSTALL_SCRIPT"; then
  echo "✅ Syntax OK"
  exit 0
else
  echo "❌ Syntax Error"
  exit 1
fi
