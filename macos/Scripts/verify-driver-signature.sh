#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "Usage: verify-driver-signature.sh path/to/HearlyAudio.driver" >&2
  exit 2
fi

DRIVER_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
SIGNATURE_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$DRIVER_PATH" 2>&1)" || {
  echo "The Hearly driver has no readable code signature." >&2
  exit 1
}

if printf '%s\n' "$SIGNATURE_DETAILS" | /usr/bin/grep -q '^Signature=adhoc$'; then
  echo "The Hearly driver is ad-hoc signed; macOS will not trust it as a HAL plug-in." >&2
  exit 1
fi

SIGNER_AUTHORITY="$(printf '%s\n' "$SIGNATURE_DETAILS" | /usr/bin/sed -nE 's/^Authority=(.*)$/\1/p' | /usr/bin/head -n 1)"
case "$SIGNER_AUTHORITY" in
  "Apple Development:"*|"Developer ID Application:"*|"Apple Distribution:"*) ;;
  *)
    echo "The Hearly driver must be signed by an Apple developer identity." >&2
    exit 1
    ;;
esac

TEAM_IDENTIFIER="$(printf '%s\n' "$SIGNATURE_DETAILS" | /usr/bin/sed -nE 's/^TeamIdentifier=(.*)$/\1/p' | /usr/bin/head -n 1)"
if [[ -z "$TEAM_IDENTIFIER" || "$TEAM_IDENTIFIER" == "not set" ]]; then
  echo "The Hearly driver signature has no developer team identity." >&2
  exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$DRIVER_PATH"; then
  echo "The Hearly driver code signature is incomplete or invalid." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_ROOT="${HEARLY_BUILD_ROOT:-$ROOT_DIR/build}"
/bin/mkdir -p "$VERIFY_ROOT"
CERT_TEMP="$(/usr/bin/mktemp -d "$VERIFY_ROOT/.hearly-driver-certificate-check.XXXXXX")"
trap '/bin/rm -rf "$CERT_TEMP"' EXIT
if ! (cd "$CERT_TEMP" && /usr/bin/codesign -d --extract-certificates "$DRIVER_PATH" >/dev/null 2>&1 && /usr/bin/security verify-cert -c codesign0 -p codeSign >/dev/null); then
  echo "The Hearly driver certificate does not validate for Apple's code-signing policy." >&2
  exit 1
fi

echo "Hearly driver code signature and Apple code-signing certificate verified."
