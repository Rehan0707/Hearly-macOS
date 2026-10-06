#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

test_output_dir=$(mktemp -d /tmp/hearly-model-test.XXXXXX)
test_vendor_dir="$PWD/Vendor/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib/lib"
test_sdk_path=$(xcrun --sdk macosx --show-sdk-path)
test_swift_path=$(xcrun --find swiftc)

"$test_swift_path" -sdk "$test_sdk_path" -target arm64-apple-macos13 -Onone \
  -I Sources/SherpaOnnx -L "$test_vendor_dir" \
  -Xlinker -rpath -Xlinker "$test_vendor_dir" \
  Sources/HearlyMac/Services/Audio/SpeakerModel.swift \
  Sources/HearlyMac/Models/VoiceProfile.swift \
  Sources/HearlyMac/Services/Persistence/LocalDatabase.swift Tests/ModelSmoke.swift \
  -o "$test_output_dir/model-smoke"
"$test_output_dir/model-smoke" "$@"
