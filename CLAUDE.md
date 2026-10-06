# CLAUDE.md — Hearly macOS

> This file is loaded into context at the start of coding sessions in this repo.
> It is the source of truth for how the native Hearly macOS app is built and structured.

---

## What Hearly is

A native Apple Silicon macOS menu-bar and desktop application providing system-wide real-time voice isolation:

1. **Voice isolation** — Only the enrolled user's voice leaves their microphone into video calls (Google Meet, Zoom, Teams, Slack). Background voices and room noise are ducked with near-zero latency.
2. **Virtual microphone** — A Core Audio `AudioServerPlugIn` HAL driver exposes `Hearly Microphone` as a virtual input device selectable across all macOS applications.
3. **Local & Privacy-first** — Voice verification and noise reduction run on-device via Sherpa-ONNX. No microphone audio is ever sent to the cloud.

---

## Architecture & Audio Pipeline

```text
Physical Microphone
  → AVAudioEngine input tap (lock-free PCM capture)
  → Serial Worker Queue (live.hearly.audio-worker)
      • Sherpa-ONNX GTCRN denoiser
      • Rolling window CAMPPlus speaker embedding extraction
      • Cosine similarity comparison against enrolled VoiceProfile
      • Target gain smoothing (1.0 for user, ~0.0 ducking)
  → VirtualMicrophoneOutput (shared memory PCM bridge)
  → AudioServerPlugIn HAL driver (in-process sample-time-tagged loopback)
  → "Hearly Microphone" (virtual input device in Meet / Zoom / Teams)
```

### Critical Audio Rules
- **Never perform model inference, disk I/O, or blocking locks in Core Audio callbacks.** All audio inference runs on the dedicated worker queue (`live.hearly.audio-worker`).
- **Enrollment vs Runtime**: "Voice training" does NOT train a model. It computes a 192-dimensional speaker embedding from acoustic speech samples and stores it locally.

---

## Commands (run from `macos/`)

```bash
swift build                        # Compile via SwiftPM
./Scripts/build-app.sh             # Build Hearly.app bundle and HAL driver
./Scripts/install-driver.sh        # Prompt macOS Installer for virtual mic driver
./Scripts/build-release.sh         # Create signed distribution zip + checksum in release/macos/
./Tests/run-ui-snapshots.sh        # Headless visual regression snapshot test runner
```

---

## Source Layout (MVVM)

```text
macos/Sources/HearlyMac/
├── App/                # HearlyMacApp.swift (menu bar extra) & HearlyAppDelegate.swift (main window)
├── Features/
│   ├── Main/           # RootView, ControlView, MenuBarView, and AppViewModel
│   ├── Settings/       # SettingsView
│   └── Previews/       # Headless previews using AppViewModel(preview: true)
├── Models/             # VoiceProfile.swift, HearlyPage.swift
├── Services/
│   ├── Audio/          # AudioEngineController, SpeakerModel, AuditionPlayer, MeetingDetector
│   ├── Accounts/       # AccountService (Supabase auth)
│   ├── Persistence/    # LocalDatabase (AES-GCM encrypted SQLite)
│   └── System/         # DriverInstallerService, GlobalHotkeyManager
├── Shared/DesignSystem # HearlyStyle (tokens, colors, glowing cards, waveforms)
Driver/                 # HearlyAudioDriver.c (Core Audio HAL AudioServerPlugIn)
Resources/Models/       # speaker-multilingual.onnx, denoiser.onnx
Vendor/                 # sherpa-onnx arm64 dylib and headers
```

---

## Conventions

- **Swift strict concurrency**: `@MainActor` on ViewModels and UI state; audio pipeline uses `@unchecked Sendable` worker isolation.
- **Preview Isolation**: `AppViewModel(preview: true)` avoids accessing hardware, database, or network.
- **Code Signing**: When staging bundles under `~/Documents`, strip Finder extended attributes (`xattr -d com.apple.FinderInfo`) to prevent FileProvider detritus during codesign verification.
