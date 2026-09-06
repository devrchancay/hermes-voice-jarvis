# Task 10 — Waveform Visualizer

## Goal
HUD-style audio wave visualization: bars or curves reacting to the
microphone input and the TTS output.

## What to do

1. Create `Views/WaveformView.swift`

2. Two modes:
   - **Input** (microphone) — shown during Listening
   - **Output** (TTS) — shown during Speaking

3. Visuals:
   - Vertical bars (equalizer style) OR a sine curve
   - Distributed horizontally below/around the orb
   - Color: blue (input) / cyan (output)
   - Height proportional to the audio level
   - Smooth animation (interpolation between frames)

4. Audio data:
   - Use the `AudioEngine` from task 09
   - For the equalizer: a basic FFT, or just samples grouped into bands
   - If the FFT is too complex: use multiple taps with simple filters,
     or simply animate random bars modulated by the RMS level

5. Layout:
   - A semicircle of bars around the orb, or a horizontal line below it
   - Pick whichever looks more Jarvis
   - Smooth fade in/out on state changes

6. Integrate into JarvisHUD:
   - Show WaveformView(mode: .input) during .listening
   - Show WaveformView(mode: .output) during .speaking
   - Hide it during .idle and .thinking

## Acceptance criteria
- [ ] The waveform is visible during listening and speaking
- [ ] It reacts to real audio (it is not random)
- [ ] Smooth animation (no frame-to-frame jumps)
- [ ] It integrates visually with the orb
- [ ] It fades out smoothly on state changes
- [ ] Stable 60fps
- [ ] Builds without warnings
