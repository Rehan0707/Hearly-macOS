#!/bin/zsh

set -euo pipefail

DRIVER_DESTINATION="/Library/Audio/Plug-Ins/HAL/HearlyAudio.driver"

if [[ ! -e "$DRIVER_DESTINATION" ]]; then
  echo "Hearly Audio Driver is not installed."
  exit 0
fi

sudo rm -rf "$DRIVER_DESTINATION"
sudo killall coreaudiod 2>/dev/null || true
echo "Removed Hearly Audio Driver. Reopen your meeting apps to refresh microphone choices."
