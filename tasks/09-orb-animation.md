# Task 09 — Orb Animation (Metal/Canvas)

## Goal
Replace the static circle with a Jarvis-style animated orb with
particles, glow, and reactions to the state.

## What to do

1. Rewrite `Views/OrbView.swift` using `Canvas` or `TimelineView`:
   - Do not use Metal directly (too complex for the MVP) — Canvas is enough

2. Base orb:
   - Circle with a radial gradient (blue center → transparent edge)
   - Diffuse outer glow (shadow with a large blur)
   - Thin, luminous outer ring

3. Per-state animations:

   **Idle:**
   - Slow pulse: scale 1.0 → 1.03 → 1.0 (3 second loop)
   - Soft intermittent glow
   - Color: dim blue

   **Listening:**
   - Scale grows to 1.2
   - The orb's edge ripples (sinusoidal distortion)
   - Microphone audio levels drive the ripple amplitude
   - Color: bright blue, intense glow

   **Thinking:**
   - Particles rotating around the orb (3-5 orbiting dots)
   - Fast pulse: 0.95 → 1.05 (0.8 second loop)
   - Color: blue → cyan transition

   **Speaking:**
   - Concentric waves expanding from the center (ripple effect)
   - Wave frequency proportional to the TTS volume
   - Color: bright blue+cyan gradient

   **Error:**
   - Fast contraction to 0.8
   - Orange flicker 2-3 times
   - Returns to idle after 3 seconds

4. Implement with `TimelineView(.animation)`:
   - Use the timestamp to compute animation phases
   - Render in Canvas: paths, gradients, shadows
   - Hold 60fps (no heavy computation inside the render)

5. Audio input:
   - Create `Core/AudioEngine.swift`
   - Use AVAudioEngine to capture audio levels (RMS/peak)
   - Expose it as `@Observable` with `var audioLevel: Float` (0.0 - 1.0)
   - OrbView consumes audioLevel to modulate the animations

## Acceptance criteria
- [ ] The orb has glow and a gradient (it is not a flat circle)
- [ ] Distinct animations for each state
- [ ] Listening reacts to the microphone audio level
- [ ] Speaking has a wave effect
- [ ] Thinking has orbiting particles
- [ ] Transitions between states are smooth (no jumps)
- [ ] Performance: stable 60fps
- [ ] Builds without warnings
