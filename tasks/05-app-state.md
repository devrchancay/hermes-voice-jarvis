# Task 05 — AppState (global state model)

## Goal
The app's central state, which coordinates the components and defines the transitions.

## What to do

1. Create `Models/AppState.swift`

2. Define the orb state (maps 1:1 to the visual states):
   ```swift
   enum OrbState {
       case idle
       case listening
       case thinking
       case speaking
       case error(String)
   }
   ```

3. Define the message model:
   ```swift
   // In Models/Message.swift
   struct Message: Identifiable {
       let id: UUID
       let role: MessageRole
       var content: String
       let timestamp: Date

       enum MessageRole: String, Codable {
           case system
           case user
           case assistant
       }
   }
   ```

4. Implement AppState:
   ```swift
   @Observable
   final class AppState {
       // State
       var orbState: OrbState = .idle
       var messages: [Message] = []
       var currentTranscript: String = ""     // what the user is saying right now
       var currentResponse: String = ""       // what Hermes is answering right now
       var isConnected: Bool = false

       // Configuration
       var serverURL: String  // persisted
       var apiKey: String     // persisted (Keychain)
       var selectedVoiceId: String?
       var activationMode: ActivationMode = .pushToTalk

       enum ActivationMode: String {
           case pushToTalk
           case continuous
       }

       // Components
       let client: HermesClient
       let recognizer: SpeechRecognizer
       let synthesizer: SpeechSynthesizer

       // Actions
       func connect() async
       func disconnect()
       func startListening()
       func stopListeningAndSend() async
       func cancelCurrentRequest()
   }
   ```

5. `connect()`:
   - Configure the client with the URL and key
   - Call `client.checkHealth()`
   - If OK → `isConnected = true`, `orbState = .idle`
   - If it fails → `orbState = .error`

6. `startListening()`:
   - `orbState = .listening`
   - `recognizer.startListening()`
   - Observe `recognizer.transcript` → update `currentTranscript`

7. `stopListeningAndSend()`:
   - `text = recognizer.stopListening()`
   - If the text is empty → go back to idle
   - Append Message(role: .user) to messages
   - `orbState = .thinking`
   - Call `client.sendMessage()` with streaming
   - First token → `orbState = .speaking`
   - Every token → `currentResponse += token`, `synthesizer.appendToken(token)`
   - Stream ends → `synthesizer.finishStreaming()`
   - Append Message(role: .assistant) to messages
   - When TTS finishes → `orbState = .idle`

8. Persistence:
   - `serverURL` in UserDefaults
   - `apiKey` in the Keychain (SecItemAdd/SecItemCopyMatching)
   - `selectedVoiceId` in UserDefaults
   - `activationMode` in UserDefaults

## Acceptance criteria
- [ ] Correct state transitions: idle → listening → thinking → speaking → idle
- [ ] Messages accumulate in the array
- [ ] Streaming works end to end: SSE tokens → currentResponse → TTS
- [ ] Configuration persists across sessions
- [ ] The API key is stored in the Keychain, not in UserDefaults
- [ ] `cancelCurrentRequest()` aborts and returns to idle
- [ ] A connection error shows the error state
- [ ] Builds without warnings
