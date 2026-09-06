//  End-to-end tests for the request/stream half of the voice loop, over a stubbed transport.

import XCTest

@testable import HermesVoice

// MARK: - Transport stub

/// Serves canned SSE responses so the loop can be exercised without a server.
final class StubURLProtocol: URLProtocol {
    /// Body returned for `/v1/chat/completions`, written as a raw SSE stream.
    nonisolated(unsafe) static var streamBody = ""
    /// Status returned for the chat endpoint.
    nonisolated(unsafe) static var chatStatus = 200
    /// Status returned for `/health`.
    nonisolated(unsafe) static var healthStatus = 200
    /// Every request that reached the transport, for assertions.
    nonisolated(unsafe) static private(set) var recordedBodies: [Data] = []
    /// Pause between SSE lines. Non-zero makes the stream cancellable mid-flight.
    nonisolated(unsafe) static var chunkDelay: Duration = .zero

    static func reset() {
        streamBody = ""
        chatStatus = 200
        healthStatus = 200
        chunkDelay = .zero
        recordedBodies = []
    }

    static var lastRequestJSON: [String: Any]? {
        guard let data = recordedBodies.last else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!

        // URLSession strips httpBody for custom protocols; the stream carries it.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            Self.recordedBodies.append(data)
        }

        let isChat = url.path.contains("chat/completions")
        let status = isChat ? Self.chatStatus : Self.healthStatus
        let body = isChat ? Data(Self.streamBody.utf8) : Data(#"{"status":"ok"}"#.utf8)

        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": isChat ? "text/event-stream" : "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        guard isChat, Self.chunkDelay > .zero else {
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // Trickle the stream out so a test can cancel part-way through. startLoading
        // already runs off the main thread, so sleeping here is fine for a stub, and
        // it keeps `self` off a Task — URLProtocol is not Sendable.
        let interval = Self.chunkDelay
        for line in Self.streamBody.components(separatedBy: "\n") {
            if cancelled.value { return }
            Thread.sleep(forTimeInterval: interval.seconds)
            if cancelled.value { return }
            client?.urlProtocol(self, didLoad: Data((line + "\n").utf8))
        }
        guard !cancelled.value else { return }
        client?.urlProtocolDidFinishLoading(self)
    }

    private let cancelled = AtomicFlag()

    override func stopLoading() {
        cancelled.set()
    }

    /// A session wired to this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Builds an SSE body from a list of content deltas.
    static func sse(tokens: [String], done: Bool = true) -> String {
        var lines = [#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#, ""]
        for token in tokens {
            let escaped = String(
                decoding: try! JSONSerialization.data(withJSONObject: [token]),
                as: UTF8.self
            )
            // Reuse JSON escaping from the array form: ["tok"] -> "tok"
            let quoted = String(escaped.dropFirst().dropLast())
            lines.append(#"data: {"choices":[{"delta":{"content":\#(quoted)}}]}"#)
            lines.append("")
        }
        if done {
            lines.append("data: [DONE]")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// A one-way flag readable from another thread.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let (secs, atto) = components
        return TimeInterval(secs) + TimeInterval(atto) / 1e18
    }
}

// MARK: - Tests

@MainActor
final class VoiceLoopTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> HermesClient {
        HermesClient(
            baseURL: "http://localhost:8642",
            apiKey: "test-key",
            session: StubURLProtocol.makeSession()
        )
    }

    // MARK: Streaming

    func testStreamYieldsEveryTokenInOrder() async throws {
        StubURLProtocol.streamBody = StubURLProtocol.sse(tokens: ["Hola", ", ", "mundo", "."])
        let client = makeClient()

        var received: [String] = []
        for try await token in client.sendMessage(
            messages: [Message(role: .user, content: "hola")],
            systemPrompt: "You are Hermes."
        ) {
            received.append(token)
        }

        XCTAssertEqual(received, ["Hola", ", ", "mundo", "."])
        XCTAssertEqual(received.joined(), "Hola, mundo.")
    }

    func testStreamStopsAtDoneSentinel() async throws {
        // A stray chunk after [DONE] must never reach the consumer.
        StubURLProtocol.streamBody = """
            data: {"choices":[{"delta":{"content":"kept"}}]}

            data: [DONE]

            data: {"choices":[{"delta":{"content":"dropped"}}]}

            """
        let client = makeClient()

        var received: [String] = []
        for try await token in client.sendMessage(messages: [], systemPrompt: nil) {
            received.append(token)
        }
        XCTAssertEqual(received, ["kept"])
    }

    func testStreamEndingWithoutDoneFinishesCleanly() async throws {
        StubURLProtocol.streamBody = StubURLProtocol.sse(tokens: ["partial"], done: false)
        let client = makeClient()

        var received: [String] = []
        for try await token in client.sendMessage(messages: [], systemPrompt: nil) {
            received.append(token)
        }
        XCTAssertEqual(received, ["partial"], "A truncated stream must not throw")
    }

    // MARK: Errors

    func testUnauthorizedIsSurfacedAsSuchNotAsADecodeFailure() async {
        StubURLProtocol.chatStatus = 401
        let client = makeClient()

        do {
            for try await _ in client.sendMessage(messages: [], systemPrompt: nil) {}
            XCTFail("A 401 must throw")
        } catch let error as HermesClientError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerErrorIsSurfacedAsUnavailable() async {
        StubURLProtocol.chatStatus = 503
        let client = makeClient()

        do {
            for try await _ in client.sendMessage(messages: [], systemPrompt: nil) {}
            XCTFail("A 503 must throw")
        } catch let error as HermesClientError {
            XCTAssertEqual(error, .serverUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHealthCheckSetsConnectedFlag() async throws {
        let client = makeClient()
        XCTAssertFalse(client.isConnected)

        let healthy = try await client.checkHealth()

        XCTAssertTrue(healthy)
        XCTAssertTrue(client.isConnected)
    }

    // MARK: Language plumbing

    func testRequestCarriesTheReplyLanguageDirective() async throws {
        StubURLProtocol.streamBody = StubURLProtocol.sse(tokens: ["ok"])
        let client = makeClient()

        let prompt = """
            You are Hermes.

            Always reply in Japanese, regardless of the language of these instructions.
            """
        for try await _ in client.sendMessage(
            messages: [Message(role: .user, content: "hi")],
            systemPrompt: prompt
        ) {}

        let json = try XCTUnwrap(StubURLProtocol.lastRequestJSON)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertTrue(
            try XCTUnwrap(messages.first?["content"]).contains("Always reply in Japanese"),
            "The directive is what makes the model answer in the chosen language"
        )
    }

    func testMultiTurnHistoryIsSentInFull() async throws {
        StubURLProtocol.streamBody = StubURLProtocol.sse(tokens: ["ok"])
        let client = makeClient()

        let history = [
            Message(role: .user, content: "first"),
            Message(role: .assistant, content: "answer"),
            Message(role: .user, content: "second"),
        ]
        for try await _ in client.sendMessage(messages: history, systemPrompt: "sys") {}

        let json = try XCTUnwrap(StubURLProtocol.lastRequestJSON)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 4, "System prompt plus all three turns")
        XCTAssertEqual(messages.map { $0["content"] }, ["sys", "first", "answer", "second"])
    }

    func testStreamRequestAsksForStreaming() async throws {
        StubURLProtocol.streamBody = StubURLProtocol.sse(tokens: ["ok"])
        let client = makeClient()
        for try await _ in client.sendMessage(messages: [], systemPrompt: nil) {}

        let json = try XCTUnwrap(StubURLProtocol.lastRequestJSON)
        XCTAssertEqual(json["stream"] as? Bool, true)
    }

    // MARK: Full loop through AppState

    func testAppStateAccumulatesResponseAndStoresBothTurns() async throws {
        StubURLProtocol.streamBody = StubURLProtocol.sse(tokens: ["Sunny", " and", " warm", "."])

        let state = AppState(previewing: true)
        state.serverURL = "http://localhost:8642"
        state.replaceClientSessionForTesting(StubURLProtocol.makeSession())
        await state.connect()
        XCTAssertTrue(state.isConnected)

        await state.send("What is the weather?")
        await state.waitForIdleForTesting()

        XCTAssertEqual(state.currentResponse, "Sunny and warm.")
        XCTAssertEqual(state.messages.count, 2)
        XCTAssertEqual(state.messages[0].role, .user)
        XCTAssertEqual(state.messages[0].content, "What is the weather?")
        XCTAssertEqual(state.messages[1].role, .assistant)
        XCTAssertEqual(state.messages[1].content, "Sunny and warm.")
    }

    func testAppStateKeepsPartialReplyWhenTheStreamFails() async throws {
        StubURLProtocol.chatStatus = 500

        let state = AppState(previewing: true)
        state.serverURL = "http://localhost:8642"
        state.replaceClientSessionForTesting(StubURLProtocol.makeSession())
        await state.connect()

        await state.send("hola")
        await state.waitForIdleForTesting(allowError: true)

        XCTAssertNotNil(state.orbState.errorMessage, "A failed stream must surface an error")
        XCTAssertEqual(state.messages.count, 1, "The user's turn is still recorded")
    }
}
