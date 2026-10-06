# Hearly — Your voice. Nothing else.

A 60-second, 1920 × 1080, 30 fps product film, with female neural narration, an original ambient score, and original vector motion graphics.

## Deliverables

- `output/Hearly-Your-Voice-60s-1080p.mp4` — H.264 video with stereo AAC audio.
- `audio/hearly_ad_mix.wav` — 48 kHz, 24-bit finished sound mix.
- `audio/voice_stem.wav` and `audio/music_stem.wav` — separate editable sound stems.
- `audio/captions.srt` — optional captions; the MP4 has no burned-in subtitles.
- `preview/contact-sheet.png` — nine-scene visual overview.
- `src/film.js` — editable deterministic Canvas motion source.
- `src/render.cjs` — frame rendering and MP4 encoding.

## Creative direction

Restrained typography, white and near-black stages, Hearly lime, floating meeting windows, on-device enrollment, animated noise isolation, and microphone → Hearly → meeting signal flow. Generic meeting interface and original illustrated avatars are conceptual product visuals. Site and source references were reviewed on 30 September 2026. The current website is a macOS waitlist; the final CTA is hearly.live.

The narration uses Microsoft Jenny neural US English speech, with “Hearly” pronounced as “Hear lee.” It is AI-generated speech. The music and final three-note sound were composed and synthesized for this film, with no stock samples. See `audio/README.md` for provenance and measurements.

## Timeline

| Seconds | Scene |
|---|---|
| 0–5 | Every meeting. Starts with you. |
| 5–10.4 | Everyday noise enters the meeting |
| 10.4–17 | Meet Hearly |
| 17–24 | On-device voice enrollment |
| 24–30.3 | Voice isolation |
| 30.3–37.3 | Keyboard, café, conversation |
| 37.3–44.5 | Select Hearly Microphone in your meeting |
| 44.5–52.5 | Microphone → Hearly → meeting |
| 52.5–60 | Your voice. Nothing else. / hearly.live |

## Render on this workstation

```bash
node /Users/rehan/Hearly-Version-1/ad/src/render.cjs preview
node /Users/rehan/Hearly-Version-1/ad/src/render.cjs render
```

The renderer uses bundled Playwright/Sharp and Chrome, plus the isolated audio environment's FFmpeg. See `audio/create_audio.py` to rebuild the sound. Nothing in the existing Hearly application source was changed.

## Render on another workstation

Install Node.js and FFmpeg. Run `npm install` and `npx playwright install chromium` in the project folder, then `npm run preview` or `npm run render`. Set `FFMPEG_PATH` or `CHROME_PATH` only if the tools are installed in a custom location. Keep the included finished mix in `audio/hearly_ad_mix.wav`; regenerating narration is optional.
