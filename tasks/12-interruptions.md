# Task 12 — Interruptions

## Goal
Let the user interrupt Hermes mid-sentence, like in a real conversation.
When the user's voice is detected during Speaking, TTS is cut off and
the app starts listening.

## What to do

1. Interruption detection:
   - While in the `.speaking` state, monitor the microphone (AudioEngine)
   - If the audio level exceeds a threshold for > 300ms → interruption
   - Configurable threshold (default: -30 dB or the RMS equivalent)

2. On detecting an interruption:
   - `synthesizer.stop()` — cut off TTS immediately
   - `client.cancel()` — cancel the SSE request if it is still in flight
   - Save the partial response as a message (whatever was said so far)
   - `recognizer.startListening()` — start listening to the user
   - `orbState = .listening`

3. Problems to solve:
   - The microphone picks up the speaker's audio (feedback loop)
   - Solution 1: use the TTS audio level to adjust the threshold dynamically
   - Solution 2: disable the microphone tap during TTS and re-enable it only
     when the speaker audio drops (simpler, less responsive)
   - Solution 3: use echo cancellation if AVAudioEngine supports it on macOS
   - Pick the simplest solution that works

4. UI:
   - On interruption, mark the response text with a trailing "..."
   - Direct speaking → listening transition (without passing through idle)

## Acceptance criteria
- [ ] Speaking during Speaking cuts off TTS
- [ ] The app starts listening immediately after cutting off
- [ ] There is no feedback loop (the app does not interrupt itself)
- [ ] The partial response is kept in the history
- [ ] The transition is visually smooth
- [ ] It works reliably (it does not trigger on ambient noise)
- [ ] Builds without warnings
