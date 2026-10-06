#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
DRIVER_DIR="$BUILD_ROOT/HearlyAudio.driver"
PACKAGE_PATH="$BUILD_ROOT/HearlyDriverInstaller.pkg"
STAGING_ROOT="$BUILD_ROOT/.HearlyDriverInstaller-root"
PKGBUILD="${PKGBUILD:-$(xcrun --find pkgbuild)}"

/bin/rm -f "$PACKAGE_PATH"
if [[ ! -d "$DRIVER_DIR" ]]; then
  echo "Build the matching HearlyAudio.driver before packaging the installer." >&2
  exit 1
fi

if ! "$SCRIPT_DIR/verify-driver-signature.sh" "$DRIVER_DIR"; then
  if [[ -n "${STRICT_RELEASE:-}" ]]; then
    echo "A trusted driver signature is required for release installer packaging." >&2
    exit 1
  fi
  echo "Skipping installer package: this development driver is not Apple-trusted." >&2
  exit 0
fi

if [[ -n "${STRICT_RELEASE:-}" && -z "${HEARLY_INSTALLER_SIGNING_IDENTITY:-}" ]]; then
  echo "STRICT_RELEASE requires HEARLY_INSTALLER_SIGNING_IDENTITY (an Installer certificate)." >&2
  exit 1
fi

DRIVER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DRIVER_DIR/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DRIVER_DIR/Contents/Info.plist")"
PACKAGE_VERSION="$DRIVER_VERSION.$BUILD_NUMBER"

/bin/rm -rf "$STAGING_ROOT"
/bin/mkdir -p "$STAGING_ROOT"
/usr/bin/ditto "$DRIVER_DIR" "$STAGING_ROOT/HearlyAudio.driver"

PKGBUILD_ARGUMENTS=(
  --root "$STAGING_ROOT"
  --identifier "live.hearely.audio-driver.installer"
  --version "$PACKAGE_VERSION"
  --install-location "/Library/Audio/Plug-Ins/HAL"
  --scripts "$SCRIPT_DIR/driver-installer-scripts"
  --ownership recommended
)
if [[ -n "${HEARLY_INSTALLER_SIGNING_IDENTITY:-}" ]]; then
  PKGBUILD_ARGUMENTS+=(--sign "$HEARLY_INSTALLER_SIGNING_IDENTITY")
fi
PKGBUILD_ARGUMENTS+=("$PACKAGE_PATH")

"$PKGBUILD" "${PKGBUILD_ARGUMENTS[@]}"
echo "Built administrator-approved installer package: $PACKAGE_PATH"
