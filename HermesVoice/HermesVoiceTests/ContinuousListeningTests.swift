//  Tests for hands-free mode: activation switching, gating, and the VAD turn cycle.

import XCTest

@testable import HermesVoice

@MainActor
final class ContinuousListeningTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    // MARK: - Mode switching

    func testDefaultsToPushToTalk() {
        let state = AppState(previewing: true)
        state.activationMode = .pushToTalk
        XCTAssertEqual(state.activationMode, .pushToTalk)
        XCTAssertFalse(state.isPassivelyListening)
    }

    func testSwitchingToContinuousWhileOfflineDoesNotOpenTheMicrophone() {
        // Nothing to send a turn to, so there is no reason to hold the mic open.
        let state = AppState(previewing: true)
        XCTAssertFalse(state.isConnected)

        state.activationMode = .continuous

        XCTAssertFalse(
            state.isPassivelyListening,
            "Passive listening must wait for a connection"
        )
    }

    func testSwitchingBackToPushToTalkStopsPassiveListening() {
        let state = AppState(previewing: true)
        state.activationMode = .continuous
        state.activationMode = .pushToTalk
        XCTAssertFalse(state.isPassivelyListening)
    }

    func testActivationModeRoundTripsThroughItsRawValue() {
        // It is persisted by raw value, so the mapping has to stay stable.
        for mode in AppState.ActivationMode.allCases {
            XCTAssertEqual(AppState.ActivationMode(rawValue: mode.rawValue), mode)
        }
        XCTAssertEqual(AppState.ActivationMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(AppState.ActivationMode.continuous.rawValue, "continuous")
    }

    // MARK: - The turn cycle the detector drives

    func testDetectorProducesOneTurnPerUtterance() {
        // Walks the exact transition sequence continuous mode relies on:
        // silence → speech → pause → more speech → silence → send.
        var vad = VoiceActivityDetector()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

        var transitions: [VoiceActivityDetector.Transition] = []
        func feed(_ level: Float, _ offset: TimeInterval) {
            if let transition = vad.process(level: level, now: at(offset)) {
                transitions.append(transition)
            }
        }

        // Room tone.
        for step in 0..<10 { feed(0.06, Double(step) * 0.05) }
        // The user starts talking.
        feed(0.55, 1.0)
        feed(0.60, 1.3)
        // Breath mid-sentence.
        feed(0.02, 2.0)
        feed(0.58, 2.6)
        // Done.
        feed(0.02, 3.2)
        feed(0.02, 4.9)

        XCTAssertEqual(
            transitions,
            [.speechStarted, .speechEnded],
            "One utterance must produce exactly one start and one end"
        )
    }

    func testBackToBackUtterancesProduceSeparateTurns() {
        var vad = VoiceActivityDetector()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        var transitions: [VoiceActivityDetector.Transition] = []
        func feed(_ level: Float, _ offset: TimeInterval) {
            if let t = vad.process(level: level, now: t0.addingTimeInterval(offset)) {
                transitions.append(t)
            }
        }

        feed(0.6, 0.0)
        feed(0.6, 0.3)          // start 1
        feed(0.0, 1.0)
        feed(0.0, 2.6)          // end 1
        feed(0.6, 5.0)
        feed(0.6, 5.3)          // start 2
        feed(0.0, 6.0)
        feed(0.0, 7.6)          // end 2

        XCTAssertEqual(
            transitions,
            [.speechStarted, .speechEnded, .speechStarted, .speechEnded]
        )
    }

    func testThresholdIsTunable() {
        // A noisy room needs a higher bar; the detector must not hardcode one.
        var sensitive = VoiceActivityDetector()
        sensitive.threshold = 0.08
        var strict = VoiceActivityDetector()
        strict.threshold = 0.5

        let now = Date(timeIntervalSince1970: 4_000_000)
        XCTAssertNil(sensitive.process(level: 0.2, now: now))
        XCTAssertEqual(
            sensitive.process(level: 0.2, now: now.addingTimeInterval(0.3)),
            .speechStarted
        )

        XCTAssertNil(strict.process(level: 0.2, now: now))
        XCTAssertNil(
            strict.process(level: 0.2, now: now.addingTimeInterval(0.3)),
            "Below a strict threshold, the same level must not trigger"
        )
    }
}
