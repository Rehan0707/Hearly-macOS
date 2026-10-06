#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/xcode-env.sh"
XCODEBUILD="${XCODEBUILD:-${DEVELOPER_DIR:-}/usr/bin/xcodebuild}"
XCODE_SCHEME="${HEARLY_XCODE_SCHEME:-Hearly}"
BUILD_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
DERIVED_DATA="${HEARLY_XCODE_DERIVED_DATA:-$BUILD_ROOT/.build-xcode}"
XCODE_BUILD_SETTINGS=("HEARLY_BUILD_ROOT=$BUILD_ROOT")
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  XCODE_BUILD_SETTINGS+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
  if [[ -z "${HEARLY_DRIVER_SIGNING_IDENTITY:-}" ]]; then
    XCODE_BUILD_SETTINGS+=("HEARLY_DRIVER_SIGNING_IDENTITY=$CODE_SIGN_IDENTITY")
  fi
fi
if [[ -n "${HEARLY_DRIVER_SIGNING_IDENTITY:-}" ]]; then
  XCODE_BUILD_SETTINGS+=("HEARLY_DRIVER_SIGNING_IDENTITY=$HEARLY_DRIVER_SIGNING_IDENTITY")
fi

if [[ ! -x "$XCODEBUILD" ]]; then
  echo "xcodebuild not found. Set DEVELOPER_DIR to an Xcode Developer directory." >&2
  exit 1
fi

cd "$ROOT_DIR"
"$XCODEBUILD" \
  -scheme "$XCODE_SCHEME" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  "${XCODE_BUILD_SETTINGS[@]}" \
  build

APP_BINARY="$BUILD_ROOT/Hearly.app/Contents/MacOS/HearlyMac"
if [[ ! -x "$APP_BINARY" ]]; then
  echo "Xcode build completed without the expected app binary: $APP_BINARY" >&2
  exit 1
fi

echo "Built $APP_BINARY"
