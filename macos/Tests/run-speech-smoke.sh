#!/bin/bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUT="$(mktemp -d /tmp/hearly-speech-smoke.XXXXXX)"
SWIFT_COMPILER="${HEARLY_SWIFTC:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc}"
SDK_PATH="${HEARLY_SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
"$SWIFT_COMPILER" -sdk "$SDK_PATH" -target arm64-apple-macos13.0 -O \
  "$TEST_ROOT/Sources/HearlyMac/Services/Audio/PhraseMatcher.swift" \
  "$TEST_ROOT/Tests/PhraseMatcherSmoke.swift" -o "$TEST_OUT/phrase-matcher"
"$TEST_OUT/phrase-matcher"
"$SWIFT_COMPILER" -sdk "$SDK_PATH" -target arm64-apple-macos13.0 -O \
  "$TEST_ROOT/Sources/HearlyMac/Services/Audio/PhraseMatcher.swift" \
  "$TEST_ROOT/Sources/HearlyMac/Services/Audio/EnrollmentSpeechRecognizer.swift" \
  "$TEST_ROOT/Sources/HearlyMac/Services/Audio/TranscriptService.swift" \
  "$TEST_ROOT/Tests/OnDeviceSpeechSmoke.swift" -o "$TEST_OUT/on-device-speech"
"$TEST_OUT/on-device-speech" "$@"
printf 'Speech test binaries: %s\n' "$TEST_OUT"
