# Task 07 — Jarvis HUD (basic main screen)

## Goal
The main screen with the Jarvis-style layout: black background, central orb
(static for now), text areas, and buttons.

## What to do

1. Create `Views/JarvisHUD.swift` — the main container

2. Layout (see the diagram in SPEC.md):
   - Background: pure black, no window chrome (use `.windowStyle(.hiddenTitleBar)`)
   - Center: a circular placeholder for the orb (a blue circle for now)
   - Above the orb: text area for the user's transcript
   - Below the orb: text area for Hermes' response
   - Bottom-left: settings button (gear icon)
   - Bottom-right: microphone button

3. Create `Views/OrbView.swift` — placeholder:
   - A Circle with a blue/cyan gradient
   - Size changes with `orbState`:
     - idle: 120pt
     - listening: 160pt
     - thinking: 140pt
     - speaking: 150pt
     - error: 100pt
   - Color changes with state:
     - idle: dim blue (opacity 0.5)
     - listening: bright blue
     - thinking: cyan
     - speaking: blue+cyan gradient
     - error: orange
   - Smooth animation between states (withAnimation(.easeInOut))

4. Create `Views/TranscriptOverlay.swift`:
   - Shows `currentTranscript` above the orb (fade in)
   - Shows `currentResponse` below the orb (appearing token by token)
   - Font: SF Mono, size 16
   - Color: white at high opacity
   - Max width: 80% of the window
   - Auto-scroll if the text is long

5. Microphone button:
   - Icon: mic.fill / mic.slash.fill depending on state
   - On press: `appState.startListening()`
   - On release: `appState.stopListeningAndSend()`
   - Style: circular, blue border, translucent black background

6. Update `ContentView.swift`:
   - Use JarvisHUD as the main view
   - Present ConnectionSheet when there is no URL
   - Inject AppState as @State

7. Update `HermesVoiceApp.swift`:
   - Window size: 500x700 (minimum)
   - `.windowStyle(.hiddenTitleBar)` for a clean look
   - Make the window draggable

## Acceptance criteria
- [ ] Dark window with no title bar
- [ ] The central orb changes color and size with the state
- [ ] Transcript text appears above the orb
- [ ] Response text appears below the orb
- [ ] The settings button opens the connection sheet
- [ ] The microphone button starts/stops recognition
- [ ] Responsive layout (looks right when resized)
- [ ] Working Previews for each subview
- [ ] Builds without warnings
