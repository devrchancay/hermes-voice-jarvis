# Task 08 — Voice Loop (end-to-end integration)

## Goal
Wire all the components together so the full flow works:
microphone → STT → Hermes API → streaming response → TTS → speaker.

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

2. Handle the system prompt:
   - The app speaks Spanish, so the prompt sent to the model stays in Spanish.
   - Default: "Eres Hermes, un asistente de voz. Responde de forma concisa
     y natural, como en una conversación hablada. Máximo 2-3 oraciones por
     respuesta a menos que se pida más detalle."
   - Make it configurable later

3. Handle multi-turn conversation:
   - Keep the messages array in AppState
   - Send the whole history on every request
   - Clear it with a button or after N messages (to stay within the context window)

4. Handle errors during the flow:
   - Network drops mid-stream → orbState = .error, show a message
   - STT fails → orbState = .error
   - TTS fails → keep showing the text, do not crash

5. Global keyboard shortcut:
   - Register a hotkey (e.g. Cmd+Shift+Space) for push-to-talk
   - Works even when the app is not focused
   - Requires Accessibility permission (show instructions if it is missing)

6. Test the full flow manually:
   - Start Hermes with the API server locally
   - Open HermesVoice, configure the URL
   - Speak → see the transcript → see the response → hear the TTS

## Acceptance criteria
- [ ] The full flow works: voice → text → API → response → voice
- [ ] The transcript appears in real time while speaking
- [ ] The response appears token by token as it arrives from the server
- [ ] TTS starts before the whole response has arrived (streaming)
- [ ] Multi-turn conversation works (context is preserved)
- [ ] Errors are handled without crashing
- [ ] The global hotkey works (or at least the UI button does)
- [ ] Builds without warnings
