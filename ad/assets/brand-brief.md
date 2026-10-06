# Hearly motion graphics reference

Inspected 2026-09-30: https://hearly.live plus local product source and UI snapshots. Local repo: /Users/rehan/Documents/Projects/Hearly-Version-1.

1. Current live visual identity: near-black #050505 canvas, white text, electric lime #BAF72B, Google Sans Flex. It uses generous negative space, pill CTAs, a centered voice-wave icon, soft green light, and fine floating luminous bars. This is stronger current authority than the older local website (lime #B5F03D, system font).
2. Use `hearly-live-logo.svg` as the current logo. It is the exact inline SVG extracted from the site's first logo image: 200×200 dark rounded square, eleven symmetric vertically centered pill bars, brightest center bar. `hearly-logo.png` is an older local asset with a different waveform and should be secondary.
3. Current landing-page product promise: “A privacy-first macOS microphone that keeps your voice clearer before it reaches Meet, Zoom, Teams, or any call app.” Visualize physical microphone → local Hearly processing → meeting window.
4. Critical label for the meeting audio picker: “Hearly Microphone”. The live Virtual Microphone card says to select it inside the meeting app. The native app repeats “After starting Hearly, select Hearly Microphone as the input in your meeting app.” Do not label the output “Hearly Mic” if faithfully reproducing it.
5. Native training labels verified in ControlView.swift: “Enroll Your Voice”, “Start Voice Training”, “Your Voice Profile”, “Test Mic”, “Preparing on-device recognition…”, “Listening to your voice”, “Phrase captured”, “Voice Enrolled”. Best ad sequence: click Start Voice Training → subtle recording waveform → checkmark and Voice Enrolled. Avoid exact completion-time promises.
6. Native controls verified: “Hearly”, “Hearly is currently active”, “Listen to Yourself”, “Microphone Input”, “Auto-Detect Meetings”; meeting banner example “Meeting Active: Zoom” and “Auto-Focus Enabled”. Supplied screenshot is a visual reference: its Hearly toggle is OFF despite the active meeting banner. Rebuild the ad state with toggle ON if showing filtering.
7. Release caution: live website is currently an Apple-silicon macOS waitlist. It says native voice isolation, driver validation, signing, notarization and clean-machine setup are gates before public download. End the ad with “Join the waitlist” and “hearly.live”, not “Install now”, “Free”, or a Chrome store CTA. Avoid promoting extra live-site features (transcription/emotion detection/summaries) outside user scope; no need for absolute “all noise removed”, performance percentages, zero latency or encryption claims.

Creative direction: 60-second premium product film in 16:9. Large precise type, dark floating macOS-like meeting and training cards, sweeping lime waveform, measured camera pushes, generous pauses. Begin with overlapping grey audio waves, then route a single lime voice through Hearly into an orderly meeting grid. The conceptual noise visual should communicate reduced distraction; it is not a measured before/after product test. Close on the exact current logo and URL.

Assets:
- hearly-live-logo.svg — exact current website SVG
- hearly-website-1920.png — live homepage screenshot
- hearly-capabilities-1920.png — live capabilities screenshot
- live-website-text.txt — captured current website text
- hearly-meeting-active.png — existing macOS snapshot, 2880×1920
- hearly-phrase-captured.png — existing macOS snapshot, 2880×1920
- hearly-enrollment-complete.png — existing macOS snapshot, 2880×1920
- hearly-logo.png — older local PNG, 512×512

Sources:
- https://hearly.live/
- macos/Sources/HearlyMac/Features/Main/Views/ControlView.swift
- macos/Sources/HearlyMac/Shared/DesignSystem/HearlyStyle.swift
- hearly-website/src/App.tsx and src/App.css (older local website)
