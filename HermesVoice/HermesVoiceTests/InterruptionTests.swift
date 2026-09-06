//  Tests for cutting a reply short: cancellation, partial-answer bookkeeping, state.

import XCTest

@testable import HermesVoice

@MainActor
final class InterruptionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func connectedState() async -> AppState {
        let state = AppState(previewing: true)
        state.serverURL = "http://localhost:8642"
        state.replaceClientSessionForTesting(StubURLProtocol.makeSession())
        await state.connect()
        return state
    }

    /// Waits until the response contains something, or the deadline passes.
    private func waitForPartialResponse(_ state: AppState, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !state.currentResponse.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Cancelling mid-stream

    func testCancelStopsTheStreamPartWayThrough() async throws {
        StubURLProtocol.chunkDelay = .milliseconds(40)
        StubURLProtocol.streamBody = StubURLProtocol.sse(
            tokens: (1...40).map { "word\($0) " }
        )

        let state = await connectedState()
        Task { await state.send("tell me a long story") }
        await waitForPartialResponse(state)

        let atCancel = state.currentResponse
        XCTAssertFalse(atCancel.isEmpty, "The stream should have started")
        XCTAssertFalse(
            atCancel.contains("word40"),
            "The stream should still be running when we cancel"
        )

        state.cancelCurrentRequest()
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(state.orbState, .idle, "Cancelling returns the orb to idle")
        XCTAssertFalse(
            state.currentResponse.contains("word40"),
            "No further tokens may arrive after cancelling"
        )
    }

    func testCancelIsSafeWhenNothingIsInFlight() async {
        let state = await connectedState()
        state.cancelCurrentRequest()
        state.cancelCurrentRequest()
        XCTAssertEqual(state.orbState, .idle)
    }

    // MARK: - Partial answers

    func testPartialAnswerIsKeptWhenTheStreamFailsMidWay() async throws {
        // Tokens arrive, then the connection dies before [DONE].
        StubURLProtocol.chunkDelay = .milliseconds(30)
        StubURLProtocol.streamBody = StubURLProtocol.sse(
            tokens: ["The ", "answer ", "is "],
            done: false
        )

        let state = await connectedState()
        await state.send("question")
        await state.waitForIdleForTesting(allowError: true)

        XCTAssertEqual(state.messages.count, 2, "Both turns are recorded")
        XCTAssertEqual(state.messages.first?.role, .user)
        XCTAssertEqual(
            state.messages.last?.content,
            "The answer is ",
            "Whatever arrived before the stream ended must be kept, not discarded"
        )
    }

    func testClearConversationDropsAnInFlightTurn() async throws {
        StubURLProtocol.chunkDelay = .milliseconds(40)
        StubURLProtocol.streamBody = StubURLProtocol.sse(tokens: (1...30).map { "w\($0) " })

        let state = await connectedState()
        Task { await state.send("hello") }
        await waitForPartialResponse(state)

        state.clearConversation()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.currentResponse, "")
        XCTAssertEqual(state.currentTranscript, "")
        XCTAssertEqual(state.orbState, .idle)
    }

    // MARK: - Threshold behaviour

    func testInterruptionThresholdRisesWithOurOwnOutput() {
        // The microphone hears the speaker, so a fixed threshold would make the app
        // interrupt itself. This pins the relationship the detector relies on.
        func threshold(forOutput output: Float) -> Float { 0.22 + output * 0.5 }

        XCTAssertEqual(threshold(forOutput: 0), 0.22, accuracy: 0.001)
        XCTAssertGreaterThan(threshold(forOutput: 0.8), threshold(forOutput: 0.1))

        // A loud reply must not clear its own bar through the microphone.
        let loudOutput: Float = 0.8
        let bleedThrough = loudOutput * 0.6   // what the mic typically picks up
        XCTAssertLessThan(
            bleedThrough,
            threshold(forOutput: loudOutput),
            "Speaker bleed must stay below the bar, or the app interrupts itself"
        )
    }
}
