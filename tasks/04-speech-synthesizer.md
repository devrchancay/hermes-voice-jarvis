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
   - `language` is a BCP-47 identifier supplied by the caller (e.g. "es-ES",
     "en-US", "ja-JP"). Never hardcode one — task 08 owns the language catalog
   - Filter `AVSpeechSynthesisVoice.speechVoices()` by exact identifier first,
     then fall back to any voice sharing the language code ("es-MX" satisfies
     "es-ES" when no exact match is installed)
   - Prefer `.premium` or `.enhanced` quality voices
   - Store the list in `availableVoices`, best quality first
   - If a voice is saved for this language, select it; otherwise select the
     highest-quality available voice
   - If no voice matches at all, leave `availableVoices` empty and set
     `state = .idle` — the caller degrades to text-only rather than crashing

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

   Sentence-end detection in `appendToken` must not assume Western punctuation.
   Match on `.`, `?`, `!`, `\n` plus their full-width and language-specific
   counterparts (`。`, `？`, `！`, `।`, `۔`). For languages that do not mark
   sentence ends this way, fall back to flushing the buffer once it exceeds a
   character threshold, so TTS never stalls waiting for a delimiter.

7. Delegate:
   - Implement `AVSpeechSynthesizerDelegate` to update `state`
   - `didStart` → .speaking
   - `didFinish` → .idle (if nothing else is queued)
   - `didCancel` → .idle

## Acceptance criteria
- [ ] Lists the installed voices for whatever language is passed in
- [ ] No language identifier is hardcoded in this file
- [ ] Falls back to a same-language voice when the exact region is unavailable
- [ ] Empty voice list is handled gracefully (no crash, caller can go text-only)
- [ ] `speak()` plays back the full text
- [ ] Streaming mode works: accumulates tokens and synthesizes per sentence
- [ ] Sentence splitting works for non-Western punctuation, and long
      delimiter-free text still flushes
- [ ] `stop()` halts playback immediately
- [ ] State updates correctly
- [ ] The selected voice persists across sessions, per language
- [ ] No crash when `stop()` is called while not speaking
- [ ] Builds without warnings
