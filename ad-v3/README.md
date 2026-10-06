# Hearly — Be heard

60-second product motion graphic. 1920 × 1080, 30 fps, H.264 MP4 with stereo AAC audio.

## Structure
- 0–7 seconds: Intro
- 7–21 seconds: The problem
- 21–50 seconds: The use case
- 50–60 seconds: Call to action

The supplied reference informed kinetic typography, device mockups, cursor movements and chapter pacing. No footage, music or branding from the reference is included.

## Assets and accuracy
No AI-generated images are used. Visuals consist of Hearly's existing SVG mark, real Hearly/Meet interface captures, and code-drawn motion graphics. Enrollment, active-state and microphone-selection interactions are animated UI demonstrations; they are not recordings of a tested end-to-end live call. The closing CTA reflects the current hearly.live waitlist.

Female narration uses Microsoft Edge Ava neural speech. Music and effects are original procedural audio. Audio stems, narration cues and subtitles are included.

## Editing and rendering
Edit src/film.js for visual timing and motion. Audio creation source is audio/create_audio.py; its dependencies are edge-tts, numpy, scipy and imageio-ffmpeg. Existing audio stems allow editing without regenerating speech.

Install Node dependencies with npm install. Set CHROME_PATH to a local Chrome executable and FFMPEG_PATH to FFmpeg if necessary. Run npm run preview or npm run render. Open preview.html to review the exported video and jump to each chapter.
