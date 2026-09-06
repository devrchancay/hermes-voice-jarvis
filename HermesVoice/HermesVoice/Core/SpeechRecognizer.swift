//  On-device speech-to-text built on SFSpeechRecognizer, fed by the shared AudioEngine.

import AVFoundation
import Foundation
import Speech
import os

// MARK: - State

enum SpeechRecognizerState: Equatable {
    case idle
    case requesting
    case listening
    case error(String)

    var isListening: Bool { self == .listening }
}

enum SpeechRecognizerError: LocalizedError {
    case unsupportedLocale(String)
    case permissionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let id):
            return "Speech recognition is not available for \(id)."
        case .permissionDenied:
            return "Microphone or speech recognition permission was denied."
        case .recognizerUnavailable:
            return "The speech recogniser is temporarily unavailable."
        }
    }
}

// MARK: - Voice activity detection

/// Detects when speech starts and stops, for hands-free (continuous) mode.
///
/// Deliberately simple: an energy gate with separate attack and release windows.
/// Ambient noise sits below the threshold; a raised voice crosses it quickly.
struct VoiceActivityDetector {
    /// Level (0...1) above which audio counts as speech.
    var threshold: Float = 0.18
    /// How long audio must stay above the threshold before speech is declared.
    var startDelay: TimeInterval = 0.2
    /// How long audio must stay below it before the utterance is considered over.
    var endDelay: TimeInterval = 1.5

    private(set) var isSpeaking = false
    private var aboveSince: Date?
    private var belowSince: Date?

    /// Feeds one level sample. Returns a transition, or nil when nothing changed.
    mutating func process(level: Float, now: Date = Date()) -> Transition? {
        if level >= threshold {
            belowSince = nil
            if aboveSince == nil { aboveSince = now }
            if !isSpeaking, let since = aboveSince, now.timeIntervalSince(since) >= startDelay {
                isSpeaking = true
                return .speechStarted
            }
        } else {
            aboveSince = nil
            if belowSince == nil { belowSince = now }
            if isSpeaking, let since = belowSince, now.timeIntervalSince(since) >= endDelay {
                isSpeaking = false
                return .speechEnded
            }
        }
        return nil
    }

    mutating func reset() {
        isSpeaking = false
        aboveSince = nil
        belowSince = nil
    }

    enum Transition: Equatable {
        case speechStarted
        case speechEnded
    }
}

// MARK: - Recognizer

/// Carries the recognition request onto the realtime audio thread.
///
/// `SFSpeechAudioBufferRecognitionRequest.append(_:)` is safe to call from the audio
/// thread, but the class predates `Sendable`, so the guarantee is asserted here.
private final class RecognitionRequestSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}

@MainActor
@Observable
final class SpeechRecognizer {
    var state: SpeechRecognizerState = .idle
    /// Live partial transcript, updated while the user speaks.
    var transcript: String = ""
    /// Last completed transcript.
    var finalTranscript: String = ""

    private(set) var locale: Locale
    /// False when the OS cannot transcribe this language without a network round-trip.
    private(set) var isOnDevice: Bool = true

    private let audioEngine: AudioEngine
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private static let logger = Logger(
        subsystem: "com.desarol.hermes-voice",
        category: "SpeechRecognizer"
    )

    init(locale: Locale, audioEngine: AudioEngine) {
        self.locale = locale
        self.audioEngine = audioEngine
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.isOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: Locale

    /// Rebuilds the underlying recogniser. Keeps the previous locale if the new one fails.
    func setLocale(_ newLocale: Locale) throws {
        guard newLocale != locale else { return }
        guard let candidate = SFSpeechRecognizer(locale: newLocale) else {
            throw SpeechRecognizerError.unsupportedLocale(newLocale.identifier)
        }
        stopListening()
        recognizer = candidate
        locale = newLocale
        isOnDevice = candidate.supportsOnDeviceRecognition
        Self.logger.info("Recogniser locale set to \(newLocale.identifier, privacy: .public)")
    }

    // MARK: Permissions

    /// Requests both speech recognition and microphone access.
    func requestPermission() async -> Bool {
        state = .requesting

        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else {
            state = .error("Speech recognition permission was denied.")
            return false
        }

        let micGranted = await AudioEngine.requestMicrophonePermission()
        guard micGranted else {
            state = .error("Microphone permission was denied.")
            return false
        }

        state = .idle
        return true
    }

    // MARK: Listening

    func startListening() throws {
        guard state != .listening else { return }
        guard let recognizer else { throw SpeechRecognizerError.unsupportedLocale(locale.identifier) }
        guard recognizer.isAvailable else { throw SpeechRecognizerError.recognizerUnavailable }

        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Honour the privacy promise wherever the OS can; the language picker
        // flags the languages where it cannot.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        // Feed the recogniser straight from the shared tap — realtime-safe.
        // `append(_:)` is documented as safe to call from the audio thread, but the
        // request type predates Sendable, so it travels in a box.
        let sink = RecognitionRequestSink(request)
        audioEngine.setInputBufferHandler { buffer, _ in
            sink.append(buffer)
        }

        do {
            try audioEngine.startInput()
        } catch {
            audioEngine.setInputBufferHandler(nil)
            self.request = nil
            state = .error(error.localizedDescription)
            throw error
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // SFSpeechRecognitionResult is not Sendable — extract plain values first.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, failure: failure)
            }
        }

        state = .listening
        Self.logger.info("Listening in \(self.locale.identifier, privacy: .public)")
    }

    /// Stops capture and returns the best transcript captured.
    @discardableResult
    func stopListening() -> String {
        guard state == .listening || request != nil else { return finalTranscript }

        audioEngine.setInputBufferHandler(nil)
        audioEngine.stopInput()

        request?.endAudio()
        task?.finish()
        request = nil
        task = nil

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { finalTranscript = text }
        if state == .listening { state = .idle }
        return text
    }

    /// Tears everything down without keeping the transcript.
    func abort() {
        audioEngine.setInputBufferHandler(nil)
        audioEngine.stopInput()
        task?.cancel()
        request?.endAudio()
        request = nil
        task = nil
        transcript = ""
        if state == .listening { state = .idle }
    }

    // MARK: Private

    private func handle(text: String?, isFinal: Bool, failure: String?) {
        if let text {
            transcript = text
            if isFinal { finalTranscript = text }
        }
        guard let failure else { return }

        // A cancelled task reports an error we deliberately caused; ignore it.
        let benign = failure.localizedCaseInsensitiveContains("cancel")
            || failure.localizedCaseInsensitiveContains("no speech")
        if !benign, state == .listening {
            Self.logger.error("Recognition failed: \(failure, privacy: .public)")
            state = .error(failure)
        }
    }
}
