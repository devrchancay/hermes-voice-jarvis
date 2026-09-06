//  Unit tests for orb state, the system prompt, and conversation bookkeeping.

import XCTest

@testable import HermesVoice

@MainActor
final class AppStateTests: XCTestCase {

    private func makeState() -> AppState {
        AppState(previewing: true)
    }

    // MARK: - Orb state

    func testStartsIdle() {
        XCTAssertEqual(makeState().orbState, .idle)
    }

    func testOrbStateLabels() {
        XCTAssertEqual(OrbState.idle.label, "READY")
        XCTAssertEqual(OrbState.listening.label, "LISTENING")
        XCTAssertEqual(OrbState.thinking.label, "PROCESSING")
        XCTAssertEqual(OrbState.speaking.label, "SPEAKING")
        XCTAssertEqual(OrbState.error("boom").label, "ERROR")
    }

    func testOnlyErrorStateCarriesAMessage() {
        XCTAssertEqual(OrbState.error("no route to host").errorMessage, "no route to host")
        XCTAssertNil(OrbState.idle.errorMessage)
        XCTAssertNil(OrbState.speaking.errorMessage)
    }

    // MARK: - System prompt

    func testPromptNamesTheReplyLanguage() {
        let state = makeState()
        let prompt = state.systemPrompt()
        XCTAssertTrue(
            prompt.contains("Always reply in \(state.language.englishName)"),
            "The reply-language directive is the whole mechanism; it must be present"
        )
    }

    func testPromptDirectiveComesLast() {
        // Placed last so a long custom prompt cannot bury it.
        let state = makeState()
        let prompt = state.systemPrompt()
        let directiveRange = try? XCTUnwrap(prompt.range(of: "Always reply in"))
        let templateRange = prompt.range(of: "voice assistant")
        if let directiveRange, let templateRange {
            XCTAssertTrue(directiveRange.lowerBound > templateRange.lowerBound)
        }
    }

    func testCustomPromptReplacesTemplateButKeepsDirective() {
        let state = makeState()
        state.customSystemPrompt = "You are a terse pirate."

        let prompt = state.systemPrompt()
        XCTAssertTrue(prompt.contains("You are a terse pirate."))
        XCTAssertFalse(prompt.contains("voice assistant"), "The template must be replaced")
        XCTAssertTrue(prompt.contains("Always reply in"), "The directive must survive")
    }

    func testBlankCustomPromptFallsBackToTemplate() {
        let state = makeState()
        state.customSystemPrompt = "   "
        XCTAssertTrue(state.systemPrompt().contains("voice assistant"))
    }

    func testDefaultTemplateForbidsMarkdown() {
        // The output is spoken aloud, so markdown would be read as punctuation.
        XCTAssertTrue(AppState.defaultPromptTemplate.contains("no markdown"))
    }

    func testDefaultTemplateIsEnglish() {
        // It instructs the model; it is not user-facing copy. Keeping it in one
        // language is what makes adding a new reply language free.
        XCTAssertTrue(AppState.defaultPromptTemplate.hasPrefix("You are Hermes"))
    }

    // MARK: - Conversation

    func testClearConversationEmptiesEverything() {
        let state = makeState()
        state.currentTranscript = "hola"
        state.clearConversation()

        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.currentTranscript, "")
        XCTAssertEqual(state.currentResponse, "")
    }

    func testSendRequiresAConnection() async {
        let state = makeState()
        XCTAssertFalse(state.isConnected)

        await state.send("hola")

        XCTAssertEqual(
            state.orbState.errorMessage,
            "Not connected. Check the server URL in settings.",
            "Sending while offline must surface an error, not fail silently"
        )
    }

    // MARK: - Configuration

    func testNeedsConfigurationTracksServerURL() {
        let state = makeState()
        state.serverURL = ""
        XCTAssertTrue(state.needsConfiguration)

        state.serverURL = "http://localhost:8642"
        XCTAssertFalse(state.needsConfiguration)
    }

    func testActivationModeLabels() {
        XCTAssertEqual(AppState.ActivationMode.pushToTalk.label, "Push to talk")
        XCTAssertEqual(AppState.ActivationMode.continuous.label, "Continuous")
        XCTAssertEqual(AppState.ActivationMode.allCases.count, 2)
    }

    func testSelectingAVoiceRecordsItAgainstTheCurrentLanguage() throws {
        let state = makeState()
        try XCTSkipIf(state.availableLanguages.isEmpty, "No speech languages installed")

        state.selectVoice(id: "com.example.voice")
        XCTAssertEqual(state.synthesizer.selectedVoiceId, "com.example.voice")

        // Clearing removes the entry rather than storing an empty string.
        state.selectVoice(id: nil)
        XCTAssertNil(state.synthesizer.selectedVoiceId)
    }
}
