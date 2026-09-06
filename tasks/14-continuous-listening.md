# Task 14 — Continuous Listening

## Goal
An "always listening" mode as an alternative to push-to-talk. The app detects
automatically when the user starts and stops speaking.

## What to do

1. Implement Voice Activity Detection (VAD) in `Core/SpeechRecognizer.swift`:
   - Monitor audio levels continuously
   - Detect speech start: audio above the threshold for > 200ms
   - Detect speech end: audio below the threshold for > 1.5 seconds
   - Configurable threshold

2. Flow in continuous mode:
   ```
   idle (listening passively)
     → speech detected → startListening() → listening
     → 1.5s of silence → stopListeningAndSend() → thinking
     → response → speaking
     → TTS finishes → back to passive listening
   ```

3. Implement in AppState:
   - If `activationMode == .continuous`:
     - After connecting, enable passive listening
     - AudioEngine runs continuously; SpeechRecognizer only once speech is detected
     - Disable it during Speaking (to avoid feedback)

4. UI:
   - Subtle indicator in the HUD: continuous mode active (a subtle wave icon)
   - The microphone button changes function: toggles continuous mode on/off
   - While passively listening, the orb has a very subtle animation
     (different from idle but not as active as listening)

5. Battery/CPU optimization:
   - AudioEngine in low-power mode during passive listening
   - Do not run SFSpeechRecognizer until speech is detected
   - Stop everything if the app goes to the background

## Acceptance criteria
- [ ] Detects speech start without a button
- [ ] Detects speech end and sends automatically
- [ ] Does not trigger on ambient noise (the threshold works)
- [ ] Can toggle between push-to-talk and continuous
- [ ] No feedback loop during Speaking
- [ ] Reasonable CPU usage during passive listening
- [ ] Builds without warnings
