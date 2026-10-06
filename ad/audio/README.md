# Hearly ad audio

60.000 seconds, stereo, 48 kHz, 24-bit PCM.

- `hearly_ad_mix.wav`: final narration + original music, ready to mux.
- `voice_stem.wav`: narration, aligned to the 60-second timeline.
- `music_stem.wav`: original ambient music, ducked below the narration, including the three-note ending logo.
- `cues.json`: exact spoken cue timings. Cue WAVs are trimmed; raw MP3 sources retain synthesis padding.
- `captions.srt`: optional caption track.
- `create_audio.py`: reproducible synthesis and mix source.

## Voice provenance

Female US English neural synthetic voice: Microsoft Edge `en-US-JennyNeural`, generated using the `edge-tts` package, rate -8%, pitch -2 Hz. No recorded human actor or celebrity voice is used. The brand was rendered as “Hear lee” in synthesis for pronunciation. Text in captions preserves “Hearly.”

The instrumental bed and short sonic logo were composed and synthesized specifically for this ad using NumPy. Warm suspended chords, sparse soft notes, a minimal pulse, and gentle stereo reflections; no sampled recordings or stock tracks.

## Validation

Exactly 2,880,000 stereo frames at 48 kHz (60.000 s). Integrated loudness -17.7 LUFS; true peak -3.2 dBFS. No overlapping narration cues; final spoken cue finishes at 56.988 s. Original logo tones enter at 57.35, 57.65, and 58.0 s; ending fades to silence at 60 s. Numeric validation and FFmpeg path are in `validation.json`.

## Rebuild

```bash
/Users/rehan/Hearly-Version-1/ad/audio/.venv/bin/python /Users/rehan/Hearly-Version-1/ad/audio/create_audio.py mix
```

Use no `mix` argument to regenerate any missing source narration through Edge TTS. Existing source files are reused.
