#!/bin/zsh

if [[ -z "${DEVELOPER_DIR:-}" || ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  selected_developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  xcode_candidates=(
    "$selected_developer_dir"
    "/Applications/Xcode.app/Contents/Developer"
    "/Applications/Xcode-beta.app/Contents/Developer"
    "$HOME/Downloads/Xcode-beta.app/Contents/Developer"
    "$HOME/Downloads/Xcode.app/Contents/Developer"
  )

  for candidate in "${xcode_candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate/usr/bin/xcodebuild" ]]; then
      export DEVELOPER_DIR="$candidate"
      break
    fi
  done
fi
