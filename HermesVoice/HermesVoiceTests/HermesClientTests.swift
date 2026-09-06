//  Unit tests for SSE parsing, request building, and URL handling. No network access.

import XCTest

@testable import HermesVoice

final class HermesClientTests: XCTestCase {

    // MARK: - SSE parsing

    func testParsesContentDelta() {
        let line = #"data: {"id":"chatcmpl-1","choices":[{"delta":{"content":"Hola"},"finish_reason":null}]}"#
        XCTAssertEqual(HermesClient.parseSSELine(line), .token("Hola"))
    }

    func testParsesDoneSentinel() {
        XCTAssertEqual(HermesClient.parseSSELine("data: [DONE]"), .done)
        XCTAssertEqual(HermesClient.parseSSELine("data:[DONE]"), .done)
    }

    func testIgnoresBlankLinesAndComments() {
        XCTAssertEqual(HermesClient.parseSSELine(""), .ignored)
        XCTAssertEqual(HermesClient.parseSSELine("   "), .ignored)
        XCTAssertEqual(HermesClient.parseSSELine(": keep-alive"), .ignored)
    }

    func testIgnoresNonDataFields() {
        XCTAssertEqual(HermesClient.parseSSELine("event: message"), .ignored)
        XCTAssertEqual(HermesClient.parseSSELine("id: 42"), .ignored)
        XCTAssertEqual(HermesClient.parseSSELine("retry: 3000"), .ignored)
    }

    func testIgnoresRoleOnlyOpeningChunk() {
        // The first chunk of an OpenAI stream carries a role and no content.
        let line = #"data: {"choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}"#
        XCTAssertEqual(HermesClient.parseSSELine(line), .ignored)
    }

    func testIgnoresFinalChunkWithoutContent() {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        XCTAssertEqual(HermesClient.parseSSELine(line), .ignored)
    }

    func testIgnoresMalformedJSON() {
        XCTAssertEqual(HermesClient.parseSSELine("data: {not json"), .ignored)
    }

    func testPreservesSignificantWhitespaceInTokens() {
        // Leading spaces matter — dropping them would run words together.
        let line = #"data: {"choices":[{"delta":{"content":" world"}}]}"#
        XCTAssertEqual(HermesClient.parseSSELine(line), .token(" world"))
    }

    func testParsesFullStreamInOrder() {
        let stream = [
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hola"}}]}"#,
            "",
            ": keep-alive",
            #"data: {"choices":[{"delta":{"content":", mundo"}}]}"#,
            "data: [DONE]",
            #"data: {"choices":[{"delta":{"content":"never"}}]}"#,
        ]

        // Mirrors the client's pump loop, which returns as soon as [DONE] arrives.
        var tokens: [String] = []
        var finished = false
        var linesConsumed = 0
        for line in stream {
            linesConsumed += 1
            switch HermesClient.parseSSELine(line) {
            case .token(let text):
                tokens.append(text)
            case .done:
                finished = true
            case .ignored:
                continue
            }
            if finished { break }
        }

        XCTAssertTrue(finished)
        XCTAssertEqual(tokens.joined(), "Hola, mundo")
        XCTAssertEqual(linesConsumed, stream.count - 1,
                       "Anything after [DONE] must never be read")
    }

    // MARK: - Request body

    func testRequestBodyShape() throws {
        let messages = [
            Message(role: .user, content: "hola"),
            Message(role: .assistant, content: "¿qué tal?"),
        ]
        let data = try HermesClient.makeRequestBody(
            model: "hermes-agent",
            messages: messages,
            systemPrompt: "You are Hermes."
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["model"] as? String, "hermes-agent")
        XCTAssertEqual(json["stream"] as? Bool, true)

        let wire = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(wire.count, 3)
        XCTAssertEqual(wire[0], ["role": "system", "content": "You are Hermes."])
        XCTAssertEqual(wire[1], ["role": "user", "content": "hola"])
        XCTAssertEqual(wire[2], ["role": "assistant", "content": "¿qué tal?"])
    }

    func testRequestBodyOmitsEmptySystemPrompt() throws {
        let data = try HermesClient.makeRequestBody(
            model: "m",
            messages: [Message(role: .user, content: "hi")],
            systemPrompt: nil
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wire = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(wire.count, 1)
        XCTAssertEqual(wire[0]["role"], "user")
    }

    func testRequestBodyDropsStoredSystemMessages() throws {
        // The live prompt is authoritative; stale system turns must not be resent.
        let messages = [
            Message(role: .system, content: "old prompt"),
            Message(role: .user, content: "hi"),
        ]
        let data = try HermesClient.makeRequestBody(
            model: "m",
            messages: messages,
            systemPrompt: "new prompt"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wire = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(wire.count, 2)
        XCTAssertEqual(wire[0]["content"], "new prompt")
        XCTAssertEqual(wire[1]["content"], "hi")
    }

    // MARK: - URL handling

    func testNormalizedBaseStripsTrailingSlashes() {
        XCTAssertEqual(HermesClient.normalizedBase("http://localhost:8642/"), "http://localhost:8642")
        XCTAssertEqual(HermesClient.normalizedBase("http://localhost:8642///"), "http://localhost:8642")
        XCTAssertEqual(HermesClient.normalizedBase("  http://x.dev  "), "http://x.dev")
    }

    func testEndpointBuildsCleanURL() {
        let url = HermesClient.endpoint(base: "http://localhost:8642", path: "/v1/chat/completions")
        XCTAssertEqual(url?.absoluteString, "http://localhost:8642/v1/chat/completions")
    }

    func testEndpointRejectsNonHTTPSchemes() {
        XCTAssertNil(HermesClient.endpoint(base: "ftp://example.com", path: "/health"))
        XCTAssertNil(HermesClient.endpoint(base: "file:///etc", path: "/health"))
        XCTAssertNil(HermesClient.endpoint(base: "localhost:8642", path: "/health"))
        XCTAssertNil(HermesClient.endpoint(base: "", path: "/health"))
    }

    func testEndpointAcceptsHTTPS() {
        let url = HermesClient.endpoint(base: "https://api.example.com", path: "/v1/models")
        XCTAssertEqual(url?.absoluteString, "https://api.example.com/v1/models")
    }

    // MARK: - Errors

    func testErrorsCarryReadableDescriptions() {
        XCTAssertNotNil(HermesClientError.invalidURL.errorDescription)
        XCTAssertNotNil(HermesClientError.unauthorized.errorDescription)
        XCTAssertNotNil(HermesClientError.serverUnavailable.errorDescription)
        XCTAssertNotNil(HermesClientError.decodingError("x").errorDescription)
        XCTAssertNotNil(HermesClientError.networkError("x").errorDescription)
    }
}
