# Hearly macOS app

This directory is the native Apple-silicon-first track for Hearly. It is isolated from the Chrome extension and uses one audio contract:

```text
physical microphone
  -> AVAudioEngine capture
  -> local processor
  -> Hearly AudioServerPlugIn output stream
  -> sample-time-tagged loopback in the driver
  -> Hearly virtual microphone input
  -> Hearly Microphone in Meet / Zoom / Teams
```

## What is included

- SwiftPM executable target for a SwiftUI menu-bar control app.
- Core Audio input-device discovery and per-session input selection.
- Microphone permission string and sandbox entitlement for app packaging.
- Core Audio output route for processed PCM and an in-process, sample-time-tagged loopback buffer in the HAL bundle.
- AudioServerPlugIn bundle that publishes `Hearly Microphone` as a virtual input device.
- Local energy-gate processor so the full capture-to-device path can be tested before native ONNX integration.

## Source layout (MVVM)

- `Sources/HearlyMac/App`: application entry point and AppKit lifecycle delegate.
- `Sources/HearlyMac/Features`: feature views, the main `AppViewModel`, and isolated SwiftUI previews.
- `Sources/HearlyMac/Models`: app navigation state and persisted voice/transcript value types.
- `Sources/HearlyMac/Services/Audio`: capture, recognition, filtering, and virtual-microphone services.
- `Sources/HearlyMac/Services/{Accounts,Persistence,System,Windowing}`: external-account, storage, hotkey, and window services.
- `Sources/HearlyMac/Shared/DesignSystem`: reusable Hearly SwiftUI styling and components.
- `Sources/HearlyAudioBridge`, `Sources/SherpaOnnx`, and `Driver`: native bridge, ONNX interface, and HAL bundle.

`AppViewModel` owns presentation state and coordinates services; feature views bind to it. The `Hearly` Xcode scheme is the full release-build wrapper (app, HAL driver, and installer), while `HearlyMac` is the underlying SwiftPM executable product. SwiftUI previews live in the package target and use `AppViewModel(preview: true)` so they avoid storage, account restoration, and device startup; there is no separate preview build target.

## Build locally

The Xcode scheme builds the app, HAL driver, and matching installer package from this checkout:

```bash
cd macos
./Scripts/build-xcode.sh
```

The outputs are `build/Hearly.app`, `build/HearlyAudio.driver`, and `build/HearlyDriverInstaller.pkg`. The app embeds that exact package under `Contents/Resources`; Audio Setup opens it with macOS Installer, which handles administrator approval. By default, the driver build selects an installed valid Apple Development identity; set `HEARLY_DRIVER_SIGNING_IDENTITY` to override it. Without a trusted signer, the app can still build locally, but the installer package is omitted and ad-hoc drivers are refused by the installer flow.

Create a versioned Apple-silicon package and checksum with:

```bash
./Scripts/build-release.sh
```

When full Xcode is installed, the scripts automatically use the selected Developer directory or a common Xcode installation under `/Applications` or `~/Downloads`. To override the detected toolchain, set its Developer directory explicitly:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-release.sh
```

Run `./Scripts/preflight-release.sh` before distribution to report missing Xcode, signing, notarization, HAL, or website-download prerequisites.

For a distributable build, set `CODE_SIGN_IDENTITY` to a valid Developer ID Application identity and `HEARLY_INSTALLER_SIGNING_IDENTITY` to a valid Installer identity. Set `NOTARY_PROFILE` to a stored `notarytool` keychain profile to submit, wait for, and staple notarization before the final zip is written. Set `STRICT_RELEASE=1` in CI to require both trusted driver signing and a signed installer package.

Install the driver only on a test machine:

```bash
./Scripts/install-driver.sh
```

Remove the driver with `./Scripts/uninstall-driver.sh`.

The package installs to `/Library/Audio/Plug-Ins/HAL/`, makes a recoverable backup of any existing Hearly driver, and restarts `coreaudiod`. macOS Installer requests administrator approval; Hearly never handles or stores the password. Quit and reopen meeting apps after installation, refresh Audio Setup, then select `Hearly Microphone` as their microphone.

## Reused vs rewritten

Reused:

- The product contract: local-first processing, optional telemetry, and no client-side secrets.
- Existing model-training and ONNX export work under `hearly-model/`.
- Existing privacy and release language under `docs/`.

Rewritten for native macOS:

- Browser `getUserMedia`, AudioWorklet, content scripts, and meeting DOM adapters are not used.
- `AVAudioEngine` owns microphone capture.
- Core Audio HAL owns the device visible to other applications.
- The driver mirrors its output stream to the published microphone input using a bounded, time-tagged loopback buffer.

## Current limitations

- The native processor is an energy gate, not the trained speaker-isolation ONNX model.
- The HAL code is a first MVP and needs live verification across Meet, Zoom, Teams, sample-rate changes, sleep/wake, and multiple clients.
- The app is sandbox-ready, but driver installation must remain a separate privileged step; do not attempt to copy into `/Library/Audio/Plug-Ins/HAL/` from the sandboxed app.
- The installer package is assembled by the same Xcode build as the driver; live installation and meeting-app routing still need administrator approval and device testing.
- Release signing, notarization, package signing, and direct website download wiring require the matching Developer ID and Installer identities.

## Release checklist

1. Replace `VoiceIsolationProcessor` with a native ONNX adapter and keep inference off the audio callback.
2. Add a bounded worker queue, underrun/overrun counters, and sample-rate conversion tests.
3. Test the driver with real Core Audio clients and verify clean uninstall/reinstall behavior.
4. Build arm64 in full Xcode, sign the app and HAL bundle with Developer ID, and enable hardened runtime.
5. Package a signed installer for the privileged HAL component; never silently modify system audio folders.
6. Notarize the app/installer, staple the ticket, and validate on a clean Apple-silicon Mac.
7. Publish versioned DMG/PKG assets from the website with checksums and a rollback link.
8. Add Sparkle or another signed updater after the first stable direct-download release.
9. Keep telemetry opt-in, local by default, and free of raw microphone audio.
10. Reuse the model and product contracts for Windows only after macOS call stability is proven.
