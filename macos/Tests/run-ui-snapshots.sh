#!/bin/bash
set -euo pipefail
HEARLY_MAC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HEARLY_MAC_ROOT"
SWIFTC="${SWIFTC:-$(xcrun --find swiftc)}"
HEARLY_SDK="$(xcrun --sdk macosx --show-sdk-path)"
HEARLY_TEMP="$(mktemp -d /tmp/hearly-ui-snapshots.XXXXXX)"
HEARLY_OUTPUT="${1:-$HEARLY_TEMP/screens}"
HEARLY_SOURCES=()
while IFS= read -r HEARLY_SOURCE; do
  HEARLY_SOURCES+=("$HEARLY_SOURCE")
done < <(find Sources/HearlyMac -name '*.swift' ! -name HearlyMacApp.swift | sort)
BRIDGE_MODULEMAP=""
for p in "$HEARLY_MAC_ROOT/.build/out/Intermediates.noindex/GeneratedModuleMaps/HearlyAudioBridge.modulemap" \
         "$HEARLY_MAC_ROOT/.build-reference/out/Intermediates.noindex/GeneratedModuleMaps/HearlyAudioBridge.modulemap"; do
  if [ -f "$p" ]; then BRIDGE_MODULEMAP="$p"; break; fi
done

if [ -z "$BRIDGE_MODULEMAP" ]; then
  mkdir -p "$HEARLY_TEMP/GeneratedModuleMaps"
  cat << 'EOF' > "$HEARLY_TEMP/GeneratedModuleMaps/HearlyAudioBridge.modulemap"
module HearlyAudioBridge {
  umbrella header "Sources/HearlyAudioBridge/include/HearlyAudioBridge.h"
  export *
}
EOF
  BRIDGE_MODULEMAP="$HEARLY_TEMP/GeneratedModuleMaps/HearlyAudioBridge.modulemap"
fi

BRIDGE_OBJ=""
for p in "$HEARLY_MAC_ROOT/.build/out/Products/Release/HearlyAudioBridge.o" \
         "$HEARLY_MAC_ROOT/.build/out/Products/Debug/HearlyAudioBridge.o" \
         "$HEARLY_MAC_ROOT/.build-reference/out/Products/Release/HearlyAudioBridge.o"; do
  if [ -f "$p" ]; then BRIDGE_OBJ="$p"; break; fi
done

if [ -z "$BRIDGE_OBJ" ]; then
  clang -c "$HEARLY_MAC_ROOT/Sources/HearlyAudioBridge/HearlyAudioBridge.c" \
    -I "$HEARLY_MAC_ROOT/Sources/HearlyAudioBridge/include" \
    -target arm64-apple-macos13 -isysroot "$HEARLY_SDK" \
    -o "$HEARLY_TEMP/HearlyAudioBridge.o"
  BRIDGE_OBJ="$HEARLY_TEMP/HearlyAudioBridge.o"
fi

"$SWIFTC" -sdk "$HEARLY_SDK" -target arm64-apple-macos13 -Onone \
  -I Sources/SherpaOnnx \
  -Xcc "-fmodule-map-file=$BRIDGE_MODULEMAP" \
  -L Vendor/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib/lib \
  -Xlinker -rpath -Xlinker "$HEARLY_MAC_ROOT/Vendor/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib/lib" \
  "${HEARLY_SOURCES[@]}" Tests/UISnapshots.swift \
  "$BRIDGE_OBJ" \
  -o "$HEARLY_TEMP/hearly-ui-snapshots"
"$HEARLY_TEMP/hearly-ui-snapshots" "$HEARLY_OUTPUT"
