//  Unit tests for voice activity detection and the language catalog. No microphone access.

import XCTest

@testable import HermesVoice

final class VoiceActivityDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testDoesNotTriggerOnBriefNoise() {
        var vad = VoiceActivityDetector()
        // A door slam: loud, but shorter than the 200 ms attack window.
        XCTAssertNil(vad.process(level: 0.9, now: start))
        XCTAssertNil(vad.process(level: 0.9, now: start.addingTimeInterval(0.1)))
        XCTAssertNil(vad.process(level: 0.0, now: start.addingTimeInterval(0.15)))
        XCTAssertFalse(vad.isSpeaking)
    }

    func testDetectsSpeechAfterAttackWindow() {
        var vad = VoiceActivityDetector()
        XCTAssertNil(vad.process(level: 0.5, now: start))
        XCTAssertNil(vad.process(level: 0.5, now: start.addingTimeInterval(0.1)))
        XCTAssertEqual(vad.process(level: 0.5, now: start.addingTimeInterval(0.25)), .speechStarted)
        XCTAssertTrue(vad.isSpeaking)
    }

    func testStaysBelowThresholdForAmbientNoise() {
        var vad = VoiceActivityDetector()
        for step in 0..<50 {
            let now = start.addingTimeInterval(Double(step) * 0.05)
            XCTAssertNil(vad.process(level: 0.10, now: now), "Ambient hum must not trigger")
        }
        XCTAssertFalse(vad.isSpeaking)
    }

    func testDetectsEndOfSpeechAfterSilence() {
        var vad = VoiceActivityDetector()
        _ = vad.process(level: 0.6, now: start)
        XCTAssertEqual(vad.process(level: 0.6, now: start.addingTimeInterval(0.3)), .speechStarted)

        // A pause shorter than the release window must not end the utterance.
        XCTAssertNil(vad.process(level: 0.0, now: start.addingTimeInterval(1.0)))
        XCTAssertNil(vad.process(level: 0.0, now: start.addingTimeInterval(2.0)))
        XCTAssertTrue(vad.isSpeaking)

        XCTAssertEqual(vad.process(level: 0.0, now: start.addingTimeInterval(2.6)), .speechEnded)
        XCTAssertFalse(vad.isSpeaking)
    }

    func testPauseMidSentenceDoesNotEndUtterance() {
        var vad = VoiceActivityDetector()
        _ = vad.process(level: 0.6, now: start)
        _ = vad.process(level: 0.6, now: start.addingTimeInterval(0.3))

        // Breath, then speech resumes — the release timer must restart from scratch.
        XCTAssertNil(vad.process(level: 0.0, now: start.addingTimeInterval(1.0)))
        XCTAssertNil(vad.process(level: 0.7, now: start.addingTimeInterval(1.8)))
        XCTAssertNil(vad.process(level: 0.0, now: start.addingTimeInterval(2.5)))
        XCTAssertTrue(vad.isSpeaking, "A 0.8 s breath must not end the turn")

        // Silence resumed at t=2.5, so the turn ends at 2.5 + 1.5 = 4.0, not before.
        XCTAssertNil(vad.process(level: 0.0, now: start.addingTimeInterval(3.5)))
        XCTAssertEqual(vad.process(level: 0.0, now: start.addingTimeInterval(4.1)), .speechEnded)
    }

    func testResetClearsState() {
        var vad = VoiceActivityDetector()
        _ = vad.process(level: 0.6, now: start)
        _ = vad.process(level: 0.6, now: start.addingTimeInterval(0.3))
        XCTAssertTrue(vad.isSpeaking)

        vad.reset()
        XCTAssertFalse(vad.isSpeaking)
        XCTAssertNil(vad.process(level: 0.6, now: start.addingTimeInterval(4.0)))
    }
}

final class SpeechLanguageTests: XCTestCase {
    func testLanguageCodeExtraction() {
        XCTAssertEqual(SpeechLanguage.languageCode(of: "es-ES"), "es")
        XCTAssertEqual(SpeechLanguage.languageCode(of: "pt_BR"), "pt")
        XCTAssertEqual(SpeechLanguage.languageCode(of: "en"), "en")
        XCTAssertEqual(SpeechLanguage.languageCode(of: "yue-CN"), "yue")
    }

    func testPickerLabelCombinesEndonymAndDisplayName() {
        let spanish = SpeechLanguage(
            id: "es-ES",
            displayName: "Spanish (Spain)",
            endonym: "español (España)",
            englishName: "Spanish",
            supportsOnDeviceRecognition: true,
            hasInstalledVoice: true
        )
        XCTAssertEqual(spanish.pickerLabel, "español (España) — Spanish (Spain)")
    }

    func testPickerLabelCollapsesWhenNamesMatch() {
        // An English UI showing English needs no "English — English".
        let english = SpeechLanguage(
            id: "en-US",
            displayName: "English (United States)",
            endonym: "English (United States)",
            englishName: "English",
            supportsOnDeviceRecognition: true,
            hasInstalledVoice: true
        )
        XCTAssertEqual(english.pickerLabel, "English (United States)")
    }

    func testCatalogOnlyListsLanguagesWithBothCapabilities() {
        // The real catalog is device-dependent; assert the invariant it must hold.
        for language in SpeechLanguageCatalog.available() {
            XCTAssertTrue(
                language.hasInstalledVoice,
                "\(language.id) was listed without an installed voice"
            )
            XCTAssertFalse(language.id.isEmpty)
            XCTAssertFalse(language.englishName.isEmpty)
        }
    }

    func testDefaultResolutionPrefersSystemLanguage() throws {
        let languages = SpeechLanguageCatalog.available()
        try XCTSkipIf(languages.isEmpty, "No speech languages installed on this machine")

        let resolved = try XCTUnwrap(SpeechLanguageCatalog.resolveDefault())
        XCTAssertTrue(languages.contains(resolved))

        let systemCode = SpeechLanguage.languageCode(
            of: Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        )
        if languages.contains(where: { $0.languageCode == systemCode }) {
            XCTAssertEqual(resolved.languageCode, systemCode,
                           "The system language is available and must win")
        }
    }

    func testUnknownSavedIdentifierFallsBackToDefault() throws {
        try XCTSkipIf(SpeechLanguageCatalog.available().isEmpty, "No speech languages installed")
        // A voice uninstalled since the setting was saved must not brick the app.
        let resolved = SpeechLanguageCatalog.language(withID: "zz-ZZ")
        XCTAssertEqual(resolved, SpeechLanguageCatalog.resolveDefault())
    }
}
