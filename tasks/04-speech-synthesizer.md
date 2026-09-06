# Task 04 — SpeechSynthesizer (on-device TTS)

## Goal
An AVSpeechSynthesizer wrapper that reads Hermes' responses out loud,
using on-device Siri voices.

## What to do

1. Create `Core/SpeechSynthesizer.swift`

2. Define the states:
   ```swift
   enum SpeechSynthesizerState {
       case idle
       case speaking
       case paused
   }
   ```

3. Implement the class:
   ```swift
   @Observable
   final class SpeechSynthesizer {
       var state: SpeechSynthesizerState = .idle
       var availableVoices: [AVSpeechSynthesisVoice] = []
       var selectedVoiceId: String?

       func loadVoices(language: String)
       func speak(_ text: String)
       func speakStreaming()           // get ready to receive tokens
       func appendToken(_ token: String)  // add a token to the buffer
       func finishStreaming()          // flush the remaining buffer
       func stop()
       func pause()
       func resume()
   }
   ```

4. `loadVoices(language:)`:
   - Filter voices by language (default "es")
   - Prefer `.premium` or `.enhanced` quality voices
   - Store the list in `availableVoices`
   - If a voice is saved in UserDefaults, select it

5. Streaming mode (for use with SSE):
   - `speakStreaming()` → starts an internal buffer
   - `appendToken()` → accumulates tokens. When it detects a sentence end
     (`.`, `?`, `!`, `\n`), it synthesizes that complete sentence
   - `finishStreaming()` → synthesizes whatever is left in the buffer
   - This lets TTS start speaking before the full response has arrived

6. Utterance configuration:
   - Rate: `AVSpeechUtteranceDefaultSpeechRate` (tunable later)
   - Pitch: 1.0
   - Volume: 1.0
   - Voice: the selected one, or the first available for the language

7. Delegate:
   - Implement `AVSpeechSynthesizerDelegate` to update `state`
   - `didStart` → .speaking
   - `didFinish` → .idle (if nothing else is queued)
   - `didCancel` → .idle

## Acceptance criteria
- [ ] Lists the available Spanish voices
- [ ] `speak()` plays back the full text
- [ ] Streaming mode works: accumulates tokens and synthesizes per sentence
- [ ] `stop()` halts playback immediately
- [ ] State updates correctly
- [ ] The selected voice persists across sessions
- [ ] No crash when `stop()` is called while not speaking
- [ ] Builds without warnings
