# Hearly — Be heard. Be you. (Version 2)

A revised 60-second product film: an emotional human opening, a warmer female voice, a three-step explanation, actual Hearly interface captures, animated Google Meet selections, voice-isolation motion, and a human payoff.

## Deliverables

- `output/Hearly-Be-Heard-v2-60s-1080p.mp4` — 1920 × 1080, 30 fps, H.264, stereo AAC.
- `audio/hearly_ad_mix.wav` — finished 60-second sound mix; 48 kHz, stereo, 24-bit PCM.
- `audio/voice_stem.wav`, `audio/music_stem.wav`, `audio/sound_design.wav` — aligned editable sound stems.
- `output/Hearly-Be-Heard-v2.srt` — optional English captions.
- `preview/contact-sheet.png` — fourteen selected storyboard frames.
- `src/film.js` — deterministic editable Canvas animation.
- `preview.html` — local player with chapter controls.

## Story and timing

| Time | Story |
|---|---|
| 0–4.1 | You've got something worth saying |
| 4.1–10.4 | An idea, a first impression, a moment to connect |
| 10.4–15 | Life doesn't pause when you unmute |
| 15–20.2 | Meet Hearly: between the microphone and the meeting |
| 20.2–24 | Enroll your voice on your Mac |
| 24–28 | A personal, local voice profile |
| 28–33.7 | Select Hearly Microphone in Meet's audio settings |
| 33.7–41 | Noise isolation before audio reaches the call |
| 41–46.2 | A clearer connection in your meeting |
| 46.2–53 | Share the idea. Finish the thought. Be there. |
| 53–60 | Hearly. Be heard. Be you. / hearly.live |

## Interface and media provenance

Hearly home and enrollment screenshots were captured from the installed native Hearly app. The enrollment introduction uses the fictional demonstration name Maya. The voice-recording screen is not used because the native capture was clipped. No user's voice was recorded and no real voice profile was enrolled.

Google Meet's audio settings and controls were captured from its actual interface in an empty, temporary call with camera and microphone off. The exported film is an **animated product walkthrough**: the microphone selection and active call state are composited demonstrations, not a live recorded integration test. The participants are original AI-generated advertising images, not real meeting attendees. Native interface captures, camera movement, cursor actions and UI overlays were composited in Canvas. The empty call was closed after capture.

Voice: Microsoft `en-US-AvaMultilingualNeural`, generated via Edge TTS at -12% base rate, with pitch-preserving cue timing. Hearly is spoken as “Hear lee.” The voice is synthetic. The ambient score, felt-synth motif, soft pulse, transitions and ending tones were created specifically for this film using NumPy and SciPy; no stock music, samples or reference-video footage was reused.

## References studied

- [Apple — Quiet the Noise](https://annierosensavinar.com/quiet-the-noise): human stakes and the visual feeling of noise giving way to focus.
- [Linear — Dashboards launch and demo](https://linear.app/changelog/2025-07-24-dashboards): product-first staging and close-up interface storytelling.
- [Hearly](https://hearly.live): brand colors, waveform identity and microphone positioning.

The concepts and motion in this film are original. These references informed the direction; their footage, music and scripts are not included.

## Image generation

Built-in ImageGen was used. Selected assets are copied into this project:

- `assets/cafe-human.png`: cinematic, natural 16:9 cafe scene; a South Asian female professional in an ivory knit top speaking to her laptop, warm window light, darker left space for titles, no logos or text.
- `assets/cafe-relief.png`: identity-preserving edit of the same scene; the same woman listens with a relaxed smile, a tighter composition, same cafe and clothing, no logos or text.
- `assets/colleagues.png`: three photographic portrait panels for compositing into the demonstration call: a Black man in a blue crewneck, an East Asian woman in a beige blouse, and a white man with glasses and an olive shirt, natural listening expressions, no UI or text.

The full production prompts are saved in `assets/image-prompts.md`.

## Render

On this workstation:

```bash
node /Users/rehan/Hearly-Version-1/ad-v2/src/render.cjs preview
node /Users/rehan/Hearly-Version-1/ad-v2/src/render.cjs render
```

On another workstation, install Node.js and FFmpeg, run `npm install` and `npx playwright install chromium`, then `npm run render`. Set `FFMPEG_PATH` or `CHROME_PATH` for custom tool locations. The bundled mix avoids any need to regenerate narration. Audio regeneration requires Python packages edge-tts, numpy, scipy and imageio-ffmpeg.
