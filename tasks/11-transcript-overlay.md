# Task 11 — Transcript Overlay (HUD style)

## Goal
Improve the text overlay so it feels like a heads-up display:
monospace typography, entrance animations, subtle effects.

## What to do

1. Rewrite `Views/TranscriptOverlay.swift`

2. User text (above the orb):
   - Font: SF Mono Light, 15pt
   - Color: white, opacity 0.8
   - Appears with a typewriter effect while dictating
   - Fades out 3 seconds after it is sent
   - Subtle prefix: "▶" or no prefix

3. Hermes' response (below the orb):
   - Font: SF Mono Regular, 16pt
   - Color: white
   - Appears token by token (it already does, but now with a per-character fade-in)
   - Blinking cursor at the end while tokens arrive (blue █ block)
   - Stays visible until the next exchange
   - Auto-scroll if it exceeds the visible area

4. Decorative HUD elements (subtle):
   - Thin horizontal lines separating the text areas
   - Small timestamp in the corner (current time, HH:mm format)
   - Textual status indicator: "LISTENING" / "PROCESSING" / "CONNECTED"
     in a small font, top corner, dim color

5. Animations:
   - Smooth fade in/out (0.3s)
   - No bouncy/spring — keep the mechanical elegance
   - New text pushes the previous text up smoothly

## Acceptance criteria
- [ ] User text appears with a typewriter effect
- [ ] The response appears token by token with a cursor
- [ ] It fades out appropriately
- [ ] HUD status indicators are visible
- [ ] Consistent monospace font
- [ ] Scrolling works for long responses
- [ ] Smooth, not abrupt, transitions
- [ ] Builds without warnings
