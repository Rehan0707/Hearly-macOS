# Hearly for macOS

Hearly is a native Apple Silicon macOS application for on-device, real-time voice isolation and virtual microphone input.

Only the enrolled user's voice is passed through into video meetings (Google Meet, Zoom, Microsoft Teams, Slack); background noise, crosstalk, and other voices in the room are ducked with near-zero latency.

---

## Features

- **On-Device Sherpa-ONNX Voice Isolation**: Uses local ONNX models (`CAMPPlus` speaker verification and `GTCRN` speech denoiser) running on Apple Silicon. Zero cloud latency or audio uploads required.
- **System-Wide Virtual Microphone**: AudioServerPlugIn HAL driver publishes `Hearly Microphone` as a virtual input device selectable in any macOS meeting application.
- **Guided 3-Step Enrollment**: Interactive setup that captures and validates voice acoustics before computing a 192-dimensional speaker embedding.
- **Headphone Audition**: Real-time monitor toggleable between Raw and Filtered feeds to test voice isolation quality directly.
- **Meeting Detection & Hotkeys**: Automatic meeting detection for Zoom, Meet, and Teams with global hotkey support.
- **Secure Local Storage**: Voice profiles and transcript metadata are encrypted with AES-GCM and stored in a local database with encryption keys held in macOS Keychain.

---

## Requirements

- **Operating System**: macOS 13.0 (Ventura) or newer
- **Architecture**: Apple Silicon (`arm64`)
- **Toolchain**: Xcode 15+ / Command Line Tools (Swift 5.9+)

---

## Project Structure

```text
macos/
├── App/                # AppKit lifecycle and SwiftUI app entry point
├── Features/           # Main control window, menu bar view, settings, view models
├── Shared/DesignSystem # Hearly dark design tokens and reusable components
├── Models/             # VoiceProfile and navigation models
├── Services/
│   ├── Audio/          # CoreAudio, AVAudioEngine, Sherpa-ONNX, Audition, HAL output
│   ├── System/         # HAL driver installer service, global hotkeys
│   ├── Accounts/       # Authentication service (Supabase)
│   └── Persistence/    # AES-GCM encrypted SQLite database
├── Driver/             # Core Audio AudioServerPlugIn (C11) driver & loopback engine
├── Resources/Models/   # On-device ONNX models (speaker-multilingual.onnx, denoiser.onnx)
├── Vendor/             # Sherpa-ONNX native C-API & runtime libraries (arm64)
├── Scripts/            # Build, codesign, driver installation, and release packaging scripts
└── Tests/              # Headless UI visual snapshot tests & smoke tests
```

---

## Building and Running

### Build via Swift Package Manager
```bash
cd macos
swift build
```

### Build Complete Application Bundle (`Hearly.app`)
```bash
cd macos
./Scripts/build-app.sh
```
This builds `build/Hearly.app`, compiles the HAL driver `build/HearlyAudio.driver`, and stages the installer package `build/HearlyDriverInstaller.pkg`.

### Install Virtual Microphone Driver
```bash
cd macos
./Scripts/install-driver.sh
```
This launches macOS Installer to place the HAL driver into `/Library/Audio/Plug-Ins/HAL` and restarts `coreaudiod`.

### Build Distributable Release Package
```bash
cd macos
./Scripts/build-release.sh
```
Generates a versioned Apple Silicon release archive and SHA-256 checksum in `release/macos/`.

### Run Visual Regression Tests (UI Snapshots)
```bash
cd macos
./Tests/run-ui-snapshots.sh macos-snapshots
```
Renders headless visual snapshot PNGs for all app screens into `macos/macos-snapshots/`.
