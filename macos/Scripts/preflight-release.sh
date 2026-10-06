#!/bin/zsh

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/xcode-env.sh"
BUILD_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
APP_DIR="$BUILD_ROOT/Hearly.app"
DRIVER_DIR="$BUILD_ROOT/HearlyAudio.driver"
INSTALLER_PACKAGE="$BUILD_ROOT/HearlyDriverInstaller.pkg"
failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

block() {
  printf 'BLOCK %s\n' "$1"
  failures=$((failures + 1))
}

if [[ -n "${DEVELOPER_DIR:-}" && -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] && \
  "$DEVELOPER_DIR/usr/bin/xcodebuild" -version >/dev/null 2>&1; then
  pass 'Full Xcode is selected'
else
  block 'Full Xcode is not selected; xcodebuild is unavailable'
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -v 'CSSMERR_TP_CERT_REVOKED' | grep -q 'Developer ID Application:'; then
  pass 'Developer ID Application identity is available'
else
  block 'Developer ID Application identity is unavailable'
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  pass 'Notary profile is configured for this shell'
else
  block 'NOTARY_PROFILE is not configured'
fi

if [[ -x "$APP_DIR/Contents/MacOS/HearlyMac" && -f "$APP_DIR/Contents/Info.plist" ]]; then
  pass 'App build output exists'
else
  block 'App build output is missing'
fi

if [[ -x "$DRIVER_DIR/Contents/MacOS/HearlyAudioDriver" && -f "$DRIVER_DIR/Contents/Info.plist" ]]; then
  pass 'HAL build output exists'
else
  block 'HAL build output is missing'
fi

if [[ -d "$APP_DIR" ]]; then
  if codesign --verify --deep "$APP_DIR" >/dev/null 2>&1; then
    pass 'App signature verifies'
  else
    block 'App signature does not verify'
  fi
fi

if [[ -d "$DRIVER_DIR" ]]; then
  if "$SCRIPT_DIR/verify-driver-signature.sh" "$DRIVER_DIR" >/dev/null 2>&1; then
    pass 'HAL signature chains to Apple'
  else
    block 'HAL driver is not signed by an Apple-trusted developer identity'
  fi
fi

if [[ -f "$INSTALLER_PACKAGE" ]]; then
  pass 'HAL installer package exists'
  if pkgutil --check-signature "$INSTALLER_PACKAGE" >/dev/null 2>&1; then
    pass 'HAL installer package signature verifies'
  else
    block 'HAL installer package is unsigned or untrusted'
  fi
else
  block 'HAL installer package is missing'
fi

if system_profiler SPAudioDataType 2>/dev/null | grep -qi 'Hearly Microphone'; then
  pass 'Hearly Microphone is visible to Core Audio'
else
  block 'Hearly Microphone is not visible; install the HAL driver for live testing'
fi

if [[ -n "${VITE_MACOS_DOWNLOAD_URL:-}" ]]; then
  pass 'Website macOS download URL is configured'
else
  block 'VITE_MACOS_DOWNLOAD_URL is not configured'
fi

DEFAULT_NATIVE_MODEL="$APP_DIR/Contents/Resources/Models/speaker-multilingual.onnx"
ACTIVE_NATIVE_MODEL="${HEARLY_NATIVE_MODEL:-$DEFAULT_NATIVE_MODEL}"
if [[ -f "$ACTIVE_NATIVE_MODEL" ]]; then
  pass "Native ONNX model is present ($(/usr/bin/basename "$ACTIVE_NATIVE_MODEL"))"
else
  block 'Native ONNX model is missing; bundled speaker-multilingual.onnx not found'
fi

if (( failures > 0 )); then
  printf '\n%s release gate(s) still need attention.\n' "$failures"
  exit 1
fi

printf '\nAll macOS release gates are ready.\n'
