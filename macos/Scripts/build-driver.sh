#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/xcode-env.sh"
cd "$ROOT_DIR"

BUILD_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
DRIVER_DIR="$BUILD_ROOT/HearlyAudio.driver"
DRIVER_VERSION="${HEARLY_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Driver/HearlyAudio.driver/Contents/Info.plist")}"
BUILD_NUMBER="${HEARLY_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Driver/HearlyAudio.driver/Contents/Info.plist")}"
CLANG="${CLANG:-$(xcrun --find clang)}"
SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
rm -rf "$DRIVER_DIR"
mkdir -p "$DRIVER_DIR/Contents/MacOS" "$DRIVER_DIR/Contents/Resources"
cp "$ROOT_DIR/Driver/HearlyAudio.driver/Contents/Info.plist" "$DRIVER_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $DRIVER_VERSION" "$DRIVER_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$DRIVER_DIR/Contents/Info.plist"

"$CLANG" -isysroot "$SDKROOT" -arch arm64 -mmacosx-version-min=13.0 -std=c11 -fPIC -bundle \
  -Wno-unused-parameter \
  -I "$ROOT_DIR/Driver" \
  -framework CoreAudio \
  -framework CoreFoundation \
  "$ROOT_DIR/Driver/HearlyAudioDriver.c" \
  -Wl,-exported_symbol,_HearlyAudioDriverFactory \
  -o "$DRIVER_DIR/Contents/MacOS/HearlyAudioDriver"

if [[ -n "${HEARLY_DRIVER_SIGNING_IDENTITY:-}" ]]; then
  SIGNING_SELECTOR="$HEARLY_DRIVER_SIGNING_IDENTITY"
elif [[ -n "${CODE_SIGN_IDENTITY:-}" && "$CODE_SIGN_IDENTITY" != "-" ]]; then
  SIGNING_SELECTOR="$CODE_SIGN_IDENTITY"
else
  SIGNING_SELECTOR="Apple Development"
fi

case "$SIGNING_SELECTOR" in
  "Apple Development")
    SIGNING_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -v "CSSMERR_TP_CERT_REVOKED" | /usr/bin/sed -nE 's/^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "Apple Development:[^"]*"$/\1/p' | /usr/bin/head -n 1)"
    ;;
  "Developer ID Application")
    SIGNING_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -v "CSSMERR_TP_CERT_REVOKED" | /usr/bin/sed -nE 's/^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "Developer ID Application:[^"]*"$/\1/p' | /usr/bin/head -n 1)"
    ;;
  "-")
    SIGNING_IDENTITY="-"
    ;;
  *)
    SIGNING_IDENTITY="$SIGNING_SELECTOR"
    ;;
esac

if [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$DRIVER_DIR"
  "$SCRIPT_DIR/verify-driver-signature.sh" "$DRIVER_DIR"
else
  if [[ -n "${STRICT_RELEASE:-}" ]]; then
    echo "A trusted Apple Development or Developer ID Application identity is required for a release driver." >&2
    exit 1
  fi
  if [[ "$SIGNING_SELECTOR" != "Apple Development" && "$SIGNING_SELECTOR" != "-" ]]; then
    echo "Requested driver signing identity was not found: $SIGNING_SELECTOR" >&2
    exit 1
  fi
  echo "Warning: no valid Apple Development identity was selected; building an ad-hoc driver. Installer packaging will be skipped." >&2
  codesign --force --deep --sign - "$DRIVER_DIR"
fi

echo "Built $DRIVER_DIR"
