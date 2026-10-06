# Audio regression fixtures

Run from `macos`: `bash Tests/run-model-smoke.sh` (Apple Silicon, Xcode).
Pass `speaker.onnx` as an argument to reproduce the English-only model's
Chinese-fixture failure. That older model is no longer the app default.

These public upstream speaker-recognition examples are development fixtures,
not user voice data. Do not ship the WAVs in the application bundle.

Source: [sherpa-onnx speaker recognition release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models).
Download base: `https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/`.

| Local file | Upstream filename | SHA-256 |
| --- | --- | --- |
| speaker-a.wav | fangjun-sr-1.wav | 33c24061180224d2350143ee19e3af031446995c676bd25996325d34bb20a4d5 |
| speaker-a-test.wav | fangjun-test-sr-1.wav | 9175e523081bf6a630ce72a55b05f92148eaafaf58cbbbe743686cd81c50848e |
| speaker-a-test-2.wav | fangjun-test-sr-2.wav | c55912144a28817a67d5eac806e5952ffcd29b82db3925f46d33df4c5f038907 |
| speaker-b-test.wav | leijun-test-sr-1.wav | 36cda04ee4d10e38095de73b77c99e8e7c54347232967a9cde4cf54f7d496bab |
| speaker-b-test-2.wav | leijun-test-sr-2.wav | 84b85e7413b5348303a95bd78813e4d669b4dc70fa5a99990b9860ca6fda91e8 |
| speaker-c-test.wav | liudehua-test-sr-1.wav | a855706ad8e8253e341e3f65892c66d7dfb4bdc83675bcf38b863f2f8d167553 |

Model files currently used:

- `Resources/Models/speaker-multilingual.onnx`: upstream
  `3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx` from the same release;
  SHA-256 `aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2`.
- `Resources/Models/denoiser.onnx`: upstream `gtcrn_simple.onnx` from the
  [speech-enhancement release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speech-enhancement-models);
  SHA-256 `e77603ac0c23dac3227dd2d7135b3a585cbee2679048aecfa886657d3ae1b534`.

The test checks two independent WAV decoders agree exactly; finite, normalized
speaker embeddings; two held-out same-speaker recordings versus three recordings
from two different speakers; the same comparisons after streaming denoising;
sample counts after flushing; deterministic stationary-noise attenuation; and
rejection of non-finite audio. The initial threshold is checked, not fitted by
the test. Model changes require a new profile identifier and fresh enrollment.

Observed on 2026-09-16 with sherpa-onnx 1.13.8: same-speaker scores 0.733–0.809
(0.621–0.716 after denoising); other-speaker scores 0.008–0.165. The English-only
model previously yielded 0.576 for the same speaker and 0.886 for another speaker;
PCM decoding was identical, so this was not an AVFoundation conversion issue.

## Limits

This is a small Chinese-language regression with three speakers, not a calibrated
accuracy benchmark. It does not establish English/accent coverage, anti-spoofing,
production false-accept/reject rates, or performance with overlapping speech.
The live implementation gates denoised audio using speaker embeddings; it does
not separate overlapping speakers. Noise attenuation of a synthetic stationary
fixture does not establish suppression of every real background sound.

The app's enrollment duration currently counts audible energy, not phonetic
phrase correctness or a trained speech VAD. Live microphone permissions,
hardware changes, virtual microphone routing, cancellation timing, and a real
meeting still require manual device testing. Model redistribution licenses must
be reviewed before a public release; upstream says models have individual licenses.
