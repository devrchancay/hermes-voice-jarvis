# Task 03 — SpeechRecognizer (on-device STT)

## Goal
An SFSpeechRecognizer wrapper that transcribes microphone audio in real time,
using on-device recognition (the M1's Neural Engine).

## What to do

1. Create `Core/SpeechRecognizer.swift`

2. Define the states:
   ```swift
   enum SpeechRecognizerState {
       case idle
       case requesting    // asking for permissions
       case listening     // actively transcribing
       case error(String)
   }
   ```

3. Implement the class:
   ```swift
   @Observable
   final class SpeechRecognizer {
       var state: SpeechRecognizerState = .idle
       var transcript: String = ""       // real-time partial transcript
       var finalTranscript: String = ""  // final transcript on release
       private(set) var locale: Locale

       init(locale: Locale)

       func requestPermission() async -> Bool
       func startListening() throws
       func stopListening() -> String   // returns the final text

       /// Rebuilds the underlying SFSpeechRecognizer. Throws if the locale is
       /// unsupported, leaving the previous locale in place.
       func setLocale(_ locale: Locale) throws
   }
   ```

4. Recognizer configuration:
   - Locale: injected, never hardcoded. The caller owns the choice — task 08
     defines the language catalog and passes the selected locale in
   - For standalone testing, `Locale.current` is a reasonable default
   - `requiresOnDeviceRecognition = true` — force on-device
   - `supportsOnDeviceRecognition` — check before starting; it varies per locale,
     so re-check after every `setLocale`
   - Task type: `.dictation`

5. `requestPermission()`:
   - Request Speech Recognition permission
   - Request microphone permission (AVAudioSession on macOS, or AVCaptureDevice)
   - Return true only if both are granted

6. `startListening()`:
   - Create AVAudioEngine + input node
   - Create SFSpeechAudioBufferRecognitionRequest
   - Install a tap on the input node (hardware format)
   - Start the recognition task
   - Update `transcript` on every partial result (isFinal == false)
   - Update `finalTranscript` when isFinal == true

7. `stopListening()`:
   - Stop the audio engine
   - End the recognition request
   - Remove the tap from the input node
   - Return the accumulated final text

8. Error handling:
   - Permission denied → state = .error
   - On-device unavailable for the current locale → state = .error with a clear
     message naming the language
   - Unsupported locale passed to `setLocale` → throw, keep the previous locale
   - Audio engine failure → state = .error

## Acceptance criteria
- [ ] Requests microphone and speech recognition permissions
- [ ] Transcribes in real time (partial result visible)
- [ ] Uses on-device recognition (`requiresOnDeviceRecognition = true`)
- [ ] The locale is injected; no language identifier is hardcoded in this file
- [ ] `setLocale` swaps languages while idle and rejects unsupported locales
- [ ] Verified against at least two locales
- [ ] `stopListening()` returns clean final text
- [ ] Handles permission errors without crashing
- [ ] State transitions correctly: idle → requesting → listening → idle
- [ ] No memory leaks (audio engine stops and the tap is removed)
- [ ] Builds without warnings
