#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/Scripts/xcode-env.sh"
SCRIPT_DIR="$ROOT_DIR/Scripts"
BUILD_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
SWIFT_BUILD_ROOT="$BUILD_ROOT/swift-build"
APP_DIR="$BUILD_ROOT/Hearly.app"
INSTALLER_PACKAGE="$BUILD_ROOT/HearlyDriverInstaller.pkg"
mkdir -p "$BUILD_ROOT"

if [[ "${HEARLY_SKIP_SWIFT_BUILD:-0}" != "1" ]]; then
  swift build -c release --scratch-path "$SWIFT_BUILD_ROOT"
fi

APP_VERSION="${HEARLY_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}"
BUILD_NUMBER="${HEARLY_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Resources/Info.plist")}"
APP_BINARY="${HEARLY_APP_BINARY:-$(swift build -c release --scratch-path "$SWIFT_BUILD_ROOT" --show-bin-path)/HearlyMac}"
if [[ ! -x "$APP_BINARY" ]]; then
  echo "Hearly app binary not found: $APP_BINARY" >&2
  exit 1
fi

# The app, HAL plug-in, and admin installer are built from this same checkout.
"$SCRIPT_DIR/build-driver.sh"
"$SCRIPT_DIR/build-driver-installer.sh"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp -X "$APP_BINARY" "$APP_DIR/Contents/MacOS/HearlyMac"
cp -X "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
HEARLY_SOURCE_ICON=""
if [[ -f "$ROOT_DIR/Resources/HearlyAppIcon.png" ]]; then
  HEARLY_SOURCE_ICON="$ROOT_DIR/Resources/HearlyAppIcon.png"
elif [[ -f "$ROOT_DIR/Resources/HearlyLogo.png" ]]; then
  HEARLY_SOURCE_ICON="$ROOT_DIR/Resources/HearlyLogo.png"
elif [[ -f "$ROOT_DIR/Resources/HearlyLogo.jpg" ]]; then
  HEARLY_SOURCE_ICON="$ROOT_DIR/Resources/HearlyLogo.jpg"
fi

if [[ -n "$HEARLY_SOURCE_ICON" ]]; then
  [[ -f "$ROOT_DIR/Resources/HearlyLogo.png" ]] && cp -X "$ROOT_DIR/Resources/HearlyLogo.png" "$APP_DIR/Contents/Resources/HearlyLogo.png"
  [[ -f "$ROOT_DIR/Resources/HearlyAppIcon.png" ]] && cp -X "$ROOT_DIR/Resources/HearlyAppIcon.png" "$APP_DIR/Contents/Resources/HearlyAppIcon.png"
  [[ -f "$ROOT_DIR/Resources/HearlyLogo.jpg" ]] && cp -X "$ROOT_DIR/Resources/HearlyLogo.jpg" "$APP_DIR/Contents/Resources/HearlyLogo.jpg"
  HEARLY_ICON_TMP_ROOT="${HEARLY_ICON_TMP_ROOT:-$ROOT_DIR/.build-tmp}"
  mkdir -p "$HEARLY_ICON_TMP_ROOT"
  HEARLY_ICON_TEMP="$(mktemp -d "$HEARLY_ICON_TMP_ROOT/hearly-icon.XXXXXX")"
  mkdir -p "$HEARLY_ICON_TEMP/Hearly.iconset"
  for HEARLY_ICON_SIZE in 16 32 128 256 512; do
    sips -z "$HEARLY_ICON_SIZE" "$HEARLY_ICON_SIZE" "$HEARLY_SOURCE_ICON" -s format png --out "$HEARLY_ICON_TEMP/Hearly.iconset/icon_${HEARLY_ICON_SIZE}x${HEARLY_ICON_SIZE}.png" >/dev/null
    HEARLY_RETINA_SIZE=$((HEARLY_ICON_SIZE * 2))
    sips -z "$HEARLY_RETINA_SIZE" "$HEARLY_RETINA_SIZE" "$HEARLY_SOURCE_ICON" -s format png --out "$HEARLY_ICON_TEMP/Hearly.iconset/icon_${HEARLY_ICON_SIZE}x${HEARLY_ICON_SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns "$HEARLY_ICON_TEMP/Hearly.iconset" -o "$APP_DIR/Contents/Resources/Hearly.icns"
  rm -rf "$HEARLY_ICON_TEMP"
fi
cp -RX "$ROOT_DIR/Resources/Models" "$APP_DIR/Contents/Resources/Models"
if [[ -f "$INSTALLER_PACKAGE" ]]; then
  cp -X "$INSTALLER_PACKAGE" "$APP_DIR/Contents/Resources/HearlyDriverInstaller.pkg"
fi
# Local-only app: never bundle backend credentials or configuration.
mkdir -p "$APP_DIR/Contents/Frameworks"
cp -X "$ROOT_DIR/Vendor/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib/lib/libsherpa-onnx-c-api.dylib" "$APP_DIR/Contents/Frameworks/"
cp -X "$ROOT_DIR/Vendor/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib/lib/libonnxruntime.dylib" "$APP_DIR/Contents/Frameworks/"
if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
  CODE_SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -v "CSSMERR_TP_CERT_REVOKED" | /usr/bin/sed -nE 's/^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "Apple Development:[^"]*"$/\1/p' | /usr/bin/head -n 1)"
fi

for HEARLY_LIBRARY in "$APP_DIR"/Contents/Frameworks/*.dylib; do
  codesign --force --options runtime --sign "${CODE_SIGN_IDENTITY:--}" "$HEARLY_LIBRARY"
done
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

# Documents folder is monitored by File Provider / Finder which aggressively
# attaches com.apple.FinderInfo during bundle creation, causing codesign detritus errors.
# Stage the bundle in a temporary directory outside File Provider for signing.
HEARLY_STAGE_ROOT="${HEARLY_STAGE_ROOT:-/tmp}"
mkdir -p "$HEARLY_STAGE_ROOT"
STAGE_DIR="$(mktemp -d "$HEARLY_STAGE_ROOT/hearly-stage.XXXXXX")"
cp -R "$APP_DIR" "$STAGE_DIR/Hearly.app"
find "$STAGE_DIR/Hearly.app" -name "._*" -delete 2>/dev/null || true
dot_clean -m "$STAGE_DIR/Hearly.app" 2>/dev/null || true
xattr -cr "$STAGE_DIR/Hearly.app" 2>/dev/null || true

if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
  codesign --force --deep --options runtime --timestamp --entitlements "$ROOT_DIR/Entitlements/HearlyMac.entitlements" --sign "$CODE_SIGN_IDENTITY" "$STAGE_DIR/Hearly.app"
else
  # Hardened library validation requires a Developer ID team. Local ad-hoc
  # builds retain App Sandbox but cannot use release library validation.
  codesign --force --deep --options 0 --entitlements "$ROOT_DIR/Entitlements/HearlyMac.entitlements" --sign - "$STAGE_DIR/Hearly.app"
fi

rm -rf "$APP_DIR"
ditto "$STAGE_DIR/Hearly.app" "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
rm -rf "$STAGE_DIR"

echo "Built $APP_DIR"
