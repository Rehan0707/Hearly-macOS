#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_PATH="$SCRIPT_DIR/HearlyDriverInstaller.pkg"

if [[ ! -f "$PACKAGE_PATH" ]]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  BUILD_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
  PACKAGE_PATH="$BUILD_ROOT/HearlyDriverInstaller.pkg"
fi

if [[ ! -f "$PACKAGE_PATH" ]]; then
  echo "HearlyDriverInstaller.pkg is missing. Build Hearly from the Xcode project first." >&2
  exit 1
fi

echo "Opening macOS Installer. Review the package and approve the administrator prompt there."
exec /usr/bin/open -a /System/Library/CoreServices/Installer.app "$PACKAGE_PATH"
