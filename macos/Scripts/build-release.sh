#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/xcode-env.sh"
REPO_DIR="$(cd "$ROOT_DIR/.." && pwd)"
BUILD_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
RELEASE_DIR="${HEARLY_RELEASE_DIR:-$REPO_DIR/release/macos}"
APP_DIR="$BUILD_ROOT/Hearly.app"
DRIVER_DIR="$BUILD_ROOT/HearlyAudio.driver"
INSTALLER_PACKAGE="$BUILD_ROOT/HearlyDriverInstaller.pkg"

if [[ -n "${STRICT_RELEASE:-}" && ( -z "${CODE_SIGN_IDENTITY:-}" || "${CODE_SIGN_IDENTITY:-}" == "-" ) ]]; then
  echo "STRICT_RELEASE requires CODE_SIGN_IDENTITY." >&2
  exit 1
fi

cd "$ROOT_DIR"
if [[ -n "${DEVELOPER_DIR:-}" && -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  HEARLY_BUILD_ROOT="$BUILD_ROOT" "$ROOT_DIR/Scripts/build-xcode.sh"
else
  HEARLY_BUILD_ROOT="$BUILD_ROOT" "$ROOT_DIR/Scripts/build-app.sh"
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
DRIVER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DRIVER_DIR/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$DRIVER_VERSION" ]]; then
  echo "App and driver versions do not match: $APP_VERSION != $DRIVER_VERSION" >&2
  exit 1
fi

STAGE_VERIFY="$(mktemp -d /tmp/hearly-release-stage.XXXXXX)"
trap 'rm -rf "$STAGE_VERIFY"' EXIT
ditto "$APP_DIR" "$STAGE_VERIFY/Hearly.app"
xattr -d com.apple.FinderInfo "$STAGE_VERIFY/Hearly.app" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$STAGE_VERIFY/Hearly.app"

ditto "$DRIVER_DIR" "$STAGE_VERIFY/HearlyAudio.driver"
xattr -d com.apple.FinderInfo "$STAGE_VERIFY/HearlyAudio.driver" 2>/dev/null || true
"$ROOT_DIR/Scripts/verify-driver-signature.sh" "$STAGE_VERIFY/HearlyAudio.driver"

if [[ ! -f "$INSTALLER_PACKAGE" ]]; then
  echo "The trusted Hearly driver installer package is missing: $INSTALLER_PACKAGE" >&2
  exit 1
fi
if [[ -n "${STRICT_RELEASE:-}" ]] && ! pkgutil --check-signature "$INSTALLER_PACKAGE"; then
  echo "The Hearly installer package must be signed for a strict release." >&2
  exit 1
fi
if [[ -n "${NOTARY_PROFILE:-}" ]] && ! pkgutil --check-signature "$INSTALLER_PACKAGE"; then
  echo "NOTARY_PROFILE requires a signed Hearly installer package; set HEARLY_INSTALLER_SIGNING_IDENTITY." >&2
  exit 1
fi

PACKAGE_NAME="Hearly-macOS-${APP_VERSION}-arm64"
PACKAGE_DIR="$STAGE_VERIFY/$PACKAGE_NAME"
ZIP_PATH="$RELEASE_DIR/$PACKAGE_NAME.zip"
mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
mkdir -p "$PACKAGE_DIR"
ditto "$STAGE_VERIFY/Hearly.app" "$PACKAGE_DIR/Hearly.app"
ditto "$STAGE_VERIFY/HearlyAudio.driver" "$PACKAGE_DIR/HearlyAudio.driver"
cp -X "$INSTALLER_PACKAGE" "$PACKAGE_DIR/HearlyDriverInstaller.pkg"
cp "$ROOT_DIR/Scripts/install-driver.sh" "$PACKAGE_DIR/install-driver.sh"
cp "$ROOT_DIR/Scripts/uninstall-driver.sh" "$PACKAGE_DIR/uninstall-driver.sh"
chmod +x "$PACKAGE_DIR/install-driver.sh" "$PACKAGE_DIR/uninstall-driver.sh"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${CODE_SIGN_IDENTITY:-}" || "${CODE_SIGN_IDENTITY:-}" == "-" ]]; then
    echo "NOTARY_PROFILE requires CODE_SIGN_IDENTITY." >&2
    exit 1
  fi
  ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PACKAGE_DIR/Hearly.app"
  xcrun stapler staple "$PACKAGE_DIR/HearlyDriverInstaller.pkg"
  rm -f "$ZIP_PATH"
fi

ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
rm -rf "$PACKAGE_DIR"

echo "Built $ZIP_PATH"
echo "Checksum $ZIP_PATH.sha256"
