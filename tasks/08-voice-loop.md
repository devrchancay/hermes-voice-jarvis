# Task 08 — Voice Loop (end-to-end integration)

## Goal
Wire all the components together so the full flow works:
microphone → STT → Hermes API → streaming response → TTS → speaker.

The whole loop is language-agnostic: one setting drives recognition, synthesis,
and the language the model answers in.

## What to do

1. Integrate the full flow in AppState:
   ```
   startListening()
       → SpeechRecognizer.startListening()
       → transcript updates the UI in real time
       → orbState = .listening

   stopListeningAndSend()
       → SpeechRecognizer.stopListening() → final text
       → POST /v1/chat/completions (stream: true)
       → orbState = .thinking
       → first token arrives → orbState = .speaking
       → tokens → currentResponse += token
       → tokens → SpeechSynthesizer.appendToken(token)
       → data: [DONE] → SpeechSynthesizer.finishStreaming()
       → TTS finishes → orbState = .idle
   ```

2. Create `Models/SpeechLanguage.swift` — the single source of truth for language:

   ```swift
   /// A language the app can both hear and speak.
   struct SpeechLanguage: Identifiable, Hashable, Codable {
       let id: String        // BCP-47 identifier, e.g. "es-ES", "en-US", "pt-BR"
       let displayName: String   // localized for the UI, e.g. "Spanish (Spain)"
       let endonym: String       // in its own language, e.g. "español (España)"
       let englishName: String   // used inside the system prompt, e.g. "Spanish"
       let supportsOnDeviceRecognition: Bool
       let hasInstalledVoice: Bool

       var locale: Locale { Locale(identifier: id) }
   }

   enum SpeechLanguageCatalog {
       /// Languages the device can both transcribe and speak, sorted by displayName.
       static func available() -> [SpeechLanguage]

       /// Best language to start with, given the system locale.
       static func resolveDefault() -> SpeechLanguage
   }
   ```

3. `SpeechLanguageCatalog.available()`:
   - Start from `SFSpeechRecognizer.supportedLocales()`
   - Keep only locales that have at least one installed `AVSpeechSynthesisVoice`
     (match on language code, so "es-MX" voices satisfy "es-ES" if no exact match)
   - For each, probe `SFSpeechRecognizer(locale:)?.supportsOnDeviceRecognition`
     to fill `supportsOnDeviceRecognition`
   - Build `displayName` via `Locale.current.localizedString(forIdentifier:)`,
     `endonym` via `locale.localizedString(forIdentifier:)`, and `englishName`
     via `Locale(identifier: "en_US").localizedString(forLanguageCode:)`
   - Cache the result — this is not cheap and the set does not change at runtime

4. `SpeechLanguageCatalog.resolveDefault()`, in order:
   - `Locale.current.identifier` if it is in the available list
   - Any available locale with the same language code (e.g. system "es-EC" → "es-ES")
   - `"en-US"` if available
   - The first available language
   - If the list is empty → surface a clear error; the app cannot run without a language

5. Add the setting to AppState (task 05 already owns persistence):
   ```swift
   var language: SpeechLanguage           // persisted in UserDefaults by id
   var voiceIdsByLanguage: [String: String] = [:]   // language id → voice id
   var customSystemPrompt: String?        // nil = use the default template
   ```
   - Store only `language.id` in UserDefaults; rehydrate through the catalog on
     launch, falling back to `resolveDefault()` if the saved id is no longer available
   - Voice preference is per language, so switching back and forth keeps each choice

6. `changeLanguage(to:)` — must work mid-session:
   - `synthesizer.stop()` and `recognizer.stopListening()` first
   - Rebuild `SFSpeechRecognizer` with the new locale (task 03 takes a locale)
   - `synthesizer.loadVoices(language:)` with the new code, then select
     `voiceIdsByLanguage[newId]` if present, otherwise the best available voice
   - Keep the existing conversation history — only the system prompt changes
   - Refuse the switch and keep the previous language if the recognizer cannot be
     created for that locale; show the error inline, do not crash

7. System prompt — built at request time, never hardcoded to one language:
   ```swift
   static let defaultPromptTemplate = """
       You are Hermes, a voice assistant. Answer concisely and naturally, the way \
       you would in a spoken conversation. Keep responses to 2-3 sentences unless \
       more detail is requested. Your output is read aloud by a speech synthesizer, \
       so write plain prose: no markdown, no bullet lists, no code blocks, no emoji.
       """

   func systemPrompt() -> String {
       let base = customSystemPrompt ?? Self.defaultPromptTemplate
       return """
           \(base)

           Always reply in \(language.englishName), regardless of the language of \
           these instructions.
           """
   }
   ```
   - The template stays in English — it is an instruction to the model, not user-facing
     copy. The reply language is injected, so adding a language costs nothing
   - The directive goes last, where it is least likely to be diluted by a long prompt
   - Rebuild the prompt on every request, so a mid-conversation language switch
     takes effect on the next turn
   - `customSystemPrompt` replaces the base text only; the language directive is
     always appended

8. Handle multi-turn conversation:
   - Keep the messages array in AppState
   - Send the whole history on every request
   - Clear it with a button or after N messages (to stay within the context window)

9. Handle errors during the flow:
   - Network drops mid-stream → orbState = .error, show a message
   - STT fails → orbState = .error
   - TTS fails → keep showing the text, do not crash
   - Selected language has no installed voice → keep showing the text, skip TTS,
     and tell the user which voice to install in System Settings › Accessibility ›
     Spoken Content

10. Global keyboard shortcut:
    - Register a hotkey (e.g. Cmd+Shift+Space) for push-to-talk
    - Works even when the app is not focused
    - Requires Accessibility permission (show instructions if it is missing)

11. Test the full flow manually, in at least two languages:
    - Start Hermes with the API server locally
    - Open HermesVoice, configure the URL
    - Speak → see the transcript → see the response → hear the TTS
    - Switch the language in settings and repeat without restarting the app

## Acceptance criteria
- [ ] The full flow works: voice → text → API → response → voice
- [ ] The transcript appears in real time while speaking
- [ ] The response appears token by token as it arrives from the server
- [ ] TTS starts before the whole response has arrived (streaming)
- [ ] Multi-turn conversation works (context is preserved)
- [ ] The language catalog lists only languages the device can hear *and* speak
- [ ] The default language follows the system locale on first launch
- [ ] Verified end to end in at least two languages, one of them non-English
- [ ] Switching language mid-session works without a restart and keeps the history
- [ ] The model answers in the selected language (the prompt directive works)
- [ ] Each language remembers its own selected voice
- [ ] A language with no installed voice degrades to text-only with a clear message
- [ ] No language identifier is hardcoded anywhere outside the catalog's fallbacks
- [ ] Errors are handled without crashing
- [ ] The global hotkey works (or at least the UI button does)
- [ ] Builds without warnings
