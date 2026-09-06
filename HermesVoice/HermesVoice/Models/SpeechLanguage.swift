//  The single language setting that drives recognition, synthesis, and the reply language.

import AVFoundation
import Foundation
import Speech
import os

/// A language the device can both hear and speak.
struct SpeechLanguage: Identifiable, Hashable, Codable, Sendable {
    /// BCP-47 identifier, e.g. "es-ES", "en-US", "pt-BR".
    let id: String
    /// Localised for the UI, e.g. "Spanish (Spain)".
    let displayName: String
    /// The name in its own language, e.g. "español (España)".
    let endonym: String
    /// English name injected into the system prompt, e.g. "Spanish".
    let englishName: String
    /// Whether speech recognition for this language runs on-device.
    let supportsOnDeviceRecognition: Bool
    /// Whether at least one synthesis voice is installed for it.
    let hasInstalledVoice: Bool

    var locale: Locale { Locale(identifier: id) }

    /// Two-letter (or ISO 639) language code, e.g. "es" for "es-ES".
    var languageCode: String { Self.languageCode(of: id) }

    /// `"español (España) — Spanish (Spain)"`, collapsed when the two are equal.
    var pickerLabel: String {
        endonym.caseInsensitiveCompare(displayName) == .orderedSame
            ? displayName
            : "\(endonym) — \(displayName)"
    }

    static func languageCode(of identifier: String) -> String {
        identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
            ?? identifier
    }
}

// MARK: - Catalog

enum SpeechLanguageCatalog {
    private static let logger = Logger(
        subsystem: "com.desarol.hermes-voice",
        category: "SpeechLanguageCatalog"
    )

    /// Computed once — the installed locales and voices do not change while running.
    nonisolated(unsafe) private static var cache: [SpeechLanguage]?
    private static let cacheLock = NSLock()

    /// Languages the device can both transcribe and speak, sorted by display name.
    ///
    /// A language we can hear but not speak would leave the loop half-broken, so the
    /// list is the intersection of the two capabilities.
    static func available() -> [SpeechLanguage] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cache { return cache }

        let voiceLanguages = Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))
        let voiceCodes = Set(voiceLanguages.map(SpeechLanguage.languageCode(of:)))

        let english = Locale(identifier: "en_US")
        let uiLocale = Locale.current

        let languages: [SpeechLanguage] = SFSpeechRecognizer.supportedLocales()
            .compactMap { locale -> SpeechLanguage? in
                let id = locale.identifier.replacingOccurrences(of: "_", with: "-")
                let code = SpeechLanguage.languageCode(of: id)

                // Exact region match preferred; otherwise any voice of the same language.
                let hasVoice = voiceLanguages.contains(id) || voiceCodes.contains(code)
                guard hasVoice else { return nil }

                let recognizer = SFSpeechRecognizer(locale: locale)
                guard let recognizer, recognizer.isAvailable || recognizer.supportsOnDeviceRecognition
                else { return nil }

                let lookup = id.replacingOccurrences(of: "-", with: "_")
                return SpeechLanguage(
                    id: id,
                    displayName: uiLocale.localizedString(forIdentifier: lookup)
                        ?? uiLocale.localizedString(forLanguageCode: code)
                        ?? id,
                    endonym: locale.localizedString(forIdentifier: lookup)
                        ?? locale.localizedString(forLanguageCode: code)
                        ?? id,
                    englishName: english.localizedString(forLanguageCode: code) ?? code,
                    supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition,
                    hasInstalledVoice: true
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        logger.info("Discovered \(languages.count) usable speech languages")
        cache = languages
        return languages
    }

    /// The language to start with, given the system locale.
    ///
    /// Order: exact system locale → same language, different region → en-US → first available.
    static func resolveDefault() -> SpeechLanguage? {
        let languages = available()
        guard !languages.isEmpty else {
            logger.error("No language supports both speech recognition and synthesis")
            return nil
        }

        let systemID = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        if let exact = languages.first(where: { $0.id.caseInsensitiveCompare(systemID) == .orderedSame }) {
            return exact
        }

        let systemCode = SpeechLanguage.languageCode(of: systemID)
        if let sameLanguage = languages.first(where: { $0.languageCode == systemCode }) {
            return sameLanguage
        }

        if let english = languages.first(where: { $0.id == "en-US" }) {
            return english
        }
        return languages.first
    }

    /// Looks up a saved identifier, falling back to the default when it is gone.
    static func language(withID id: String?) -> SpeechLanguage? {
        guard let id else { return resolveDefault() }
        return available().first { $0.id == id } ?? resolveDefault()
    }

    /// Test seam: lets unit tests install a deterministic catalog.
    static func overrideCacheForTesting(_ languages: [SpeechLanguage]?) {
        cacheLock.lock()
        cache = languages
        cacheLock.unlock()
    }
}
