# Task 02 — HermesClient (HTTP + SSE Streaming)

## Goal
An HTTP client that connects to any OpenAI-compatible API server
(Hermes, OpenAI, Ollama, etc.) and processes SSE streaming.

## What to do

1. Create `Core/HermesClient.swift`

2. Define the error enum:
   ```swift
   enum HermesClientError: LocalizedError {
       case invalidURL
       case unauthorized
       case serverUnavailable
       case decodingError(String)
       case networkError(Error)
   }
   ```

3. Implement the class:
   ```swift
   @Observable
   final class HermesClient {
       var baseURL: String
       var apiKey: String
       var isConnected: Bool = false

       // Check the connection
       func checkHealth() async throws -> Bool

       // Send a message with streaming
       func sendMessage(
           messages: [Message],
           systemPrompt: String?
       ) -> AsyncThrowingStream<String, Error>

       // Cancel the in-flight request
       func cancel()
   }
   ```

4. `checkHealth()`:
   - `GET /health`
   - Returns true if status is 200 and the body contains `"ok"`
   - 5 second timeout

5. `sendMessage()`:
   - `POST /v1/chat/completions`
   - Headers: `Authorization: Bearer <apiKey>`, `Content-Type: application/json`
   - Body: `{"model": "hermes-agent", "messages": [...], "stream": true}`
   - Parse SSE: read lines starting with `data: `
   - Extract `choices[0].delta.content` from each JSON chunk
   - Yield every token as a String on the AsyncThrowingStream
   - Finish when `data: [DONE]` arrives
   - Use `URLSession.bytes(for:)` for native streaming

6. `cancel()`:
   - Cancel the in-flight URLSession task

7. Create `HermesVoiceTests/HermesClientTests.swift`:
   - SSE parsing test (mock data, no real network)
   - Request body building test
   - `[DONE]` handling test

## Acceptance criteria
- [ ] `checkHealth()` works against a real server (verified manually)
- [ ] `sendMessage()` returns individual tokens via AsyncThrowingStream
- [ ] SSE is parsed correctly (delta.content extracted)
- [ ] `[DONE]` closes the stream cleanly
- [ ] `cancel()` aborts an in-flight request
- [ ] Network errors propagate as HermesClientError
- [ ] Parsing tests pass
- [ ] Builds without warnings
