//  On-device text-to-speech: renders AVSpeechSynthesizer output to buffers we play ourselves.

import AVFoundation
import Foundation
import os

// MARK: - State

enum SpeechSynthesizerState: Equatable {
    case idle
    case speaking
    case paused
}

// MARK: - Sentence buffering

/// Accumulates streamed tokens and hands back complete sentences to speak.
///
/// Splitting on sentence boundaries is what lets speech start before the model has
/// finished answering. Terminators cover non-Western punctuation, and a length cap
/// flushes languages that do not mark sentence ends at all, so TTS never stalls.
struct SentenceBuffer {
    /// Characters that end a sentence across the scripts AVSpeechSynthesizer supports.
    static let terminators: Set<Character> = [
        ".", "?", "!", "\n",
        "。", "？", "！", "…",   // CJK
        "।", "॥",                // Devanagari
        "۔", "؟",                // Arabic / Urdu
        "።", "፧",                // Ethiopic
    ]

    /// Flush anyway once the buffer gets this long without a terminator.
    var maxLength = 180

    private var buffer = ""

    /// Appends a token, returning any sentences that are now complete.
    mutating func append(_ token: String) -> [String] {
        buffer += token
        var ready: [String] = []

        while let index = buffer.firstIndex(where: { Self.terminators.contains($0) }) {
            let sentence = String(buffer[...index])
            buffer = String(buffer[buffer.index(after: index)...])
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { ready.append(trimmed) }
        }

        // No terminator in sight — flush at a word boundary so we do not clip mid-word.
        if buffer.count >= maxLength {
            if let space = buffer.lastIndex(of: " ") {
                let chunk = String(buffer[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = String(buffer[buffer.index(after: space)...])
                if !chunk.isEmpty { ready.append(chunk) }
            } else {
                let chunk = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = ""
                if !chunk.isEmpty { ready.append(chunk) }
            }
        }
        return ready
    }

    /// Returns whatever is left and empties the buffer.
    mutating func flush() -> String? {
        let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remainder.isEmpty ? nil : remainder
    }

    mutating func reset() {
        buffer = ""
    }
}

/// Strips light markdown so the synthesiser does not read punctuation aloud.
enum SpokenTextSanitizer {
    private static let noise: Set<Character> = ["*", "_", "`", "#", "|", "~"]

    static func sanitize(_ text: String) -> String {
        String(text.filter { !noise.contains($0) })
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Synthesizer

@MainActor
@Observable
final class SpeechSynthesizer {
    private(set) var state: SpeechSynthesizerState = .idle
    private(set) var availableVoices: [AVSpeechSynthesisVoice] = []
    var selectedVoiceId: String?

    /// Rate multiplier applied to the platform default. 1.0 = default speed.
    var rateMultiplier: Float = 1.0

    /// Called on the main actor once the queue drains.
    var onFinishedSpeaking: (() -> Void)?

    private let audioEngine: AudioEngine
    private let synthesizer = AVSpeechSynthesizer()
    private var sentences = SentenceBuffer()
    private var queue: [String] = []
    private var pumpTask: Task<Void, Never>?
    private var isStreaming = false
    private var currentLanguage = "en-US"

    private static let logger = Logger(
        subsystem: "com.desarol.hermes-voice",
        category: "SpeechSynthesizer"
    )

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    // MARK: Voices

    /// Loads the installed voices for a BCP-47 language, best quality first.
    ///
    /// Falls back to any voice sharing the language code, so "es-MX" serves "es-ES"
    /// when the exact region is not installed.
    func loadVoices(language: String) {
        currentLanguage = language
        let code = SpeechLanguage.languageCode(of: language)
        let all = AVSpeechSynthesisVoice.speechVoices()

        let exact = all.filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
        let sameLanguage = all.filter { SpeechLanguage.languageCode(of: $0.language) == code }
        let matches = exact.isEmpty ? sameLanguage : exact

        availableVoices = matches.sorted { lhs, rhs in
            if lhs.quality.rank != rhs.quality.rank { return lhs.quality.rank > rhs.quality.rank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        // Keep the current pick if it still applies, otherwise take the best available.
        if let selectedVoiceId,
           availableVoices.contains(where: { $0.identifier == selectedVoiceId }) {
            return
        }
        selectedVoiceId = availableVoices.first?.identifier
        Self.logger.info(
            "Loaded \(self.availableVoices.count) voices for \(language, privacy: .public)"
        )
    }

    /// True when the selected language has no installed voice — caller goes text-only.
    var hasVoice: Bool { !availableVoices.isEmpty }

    private var activeVoice: AVSpeechSynthesisVoice? {
        if let selectedVoiceId,
           let match = availableVoices.first(where: { $0.identifier == selectedVoiceId }) {
            return match
        }
        return availableVoices.first
    }

    // MARK: Speaking

    /// Speaks a complete piece of text.
    func speak(_ text: String) {
        let clean = SpokenTextSanitizer.sanitize(text)
        guard !clean.isEmpty, hasVoice else { return }
        queue.append(clean)
        pump()
    }

    /// Prepares to receive streamed tokens.
    func speakStreaming() {
        sentences.reset()
        isStreaming = true
    }

    /// Adds a token; complete sentences are spoken as soon as they form.
    func appendToken(_ token: String) {
        guard isStreaming else { return }
        let ready = sentences.append(token)
        guard !ready.isEmpty, hasVoice else { return }
        for sentence in ready {
            let clean = SpokenTextSanitizer.sanitize(sentence)
            if !clean.isEmpty { queue.append(clean) }
        }
        pump()
    }

    /// Speaks whatever is left in the buffer and ends streaming mode.
    func finishStreaming() {
        isStreaming = false
        if let remainder = sentences.flush(), hasVoice {
            let clean = SpokenTextSanitizer.sanitize(remainder)
            if !clean.isEmpty {
                queue.append(clean)
                pump()
            }
        }
        // Nothing queued and nothing playing — the caller is waiting on us.
        if queue.isEmpty, pumpTask == nil, state == .idle {
            onFinishedSpeaking?()
        }
    }

    /// Stops immediately and discards anything queued.
    func stop() {
        isStreaming = false
        sentences.reset()
        queue.removeAll()
        pumpTask?.cancel()
        pumpTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        audioEngine.stopOutput()
        state = .idle
    }

    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    // MARK: Queue pump

    private func pump() {
        guard pumpTask == nil else { return }
        pumpTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.queue.isEmpty {
                let sentence = self.queue.removeFirst()
                await self.play(sentence)
            }
            self.pumpTask = nil
            if !Task.isCancelled {
                self.audioEngine.stopOutput()
                self.state = .idle
                // Only report completion once the model has stopped sending too.
                if !self.isStreaming { self.onFinishedSpeaking?() }
            }
        }
    }

    private func play(_ sentence: String) async {
        guard let voice = activeVoice else { return }

        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rateMultiplier
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        guard let rendered = await Self.render(utterance, using: synthesizer) else {
            // Rendering unavailable — fall back to the system playback path so the
            // user still hears the answer, just without an output waveform.
            Self.logger.notice("Buffer rendering unavailable; using direct playback")
            await speakDirectly(utterance)
            return
        }

        do {
            try audioEngine.startOutput(format: rendered.format)
        } catch {
            Self.logger.error("Output start failed: \(error.localizedDescription, privacy: .public)")
            await speakDirectly(utterance)
            return
        }

        state = .speaking
        for buffer in rendered.buffers {
            if Task.isCancelled { return }
            await audioEngine.schedule(buffer)
        }
    }

    private func speakDirectly(_ utterance: AVSpeechUtterance) async {
        state = .speaking
        synthesizer.speak(utterance)
        while synthesizer.isSpeaking, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: Rendering

    private struct RenderedSpeech {
        let format: AVAudioFormat
        let buffers: [AVAudioPCMBuffer]
    }

    /// Renders an utterance to PCM buffers converted to the engine's float format.
    private static func render(
        _ utterance: AVSpeechUtterance,
        using synthesizer: AVSpeechSynthesizer
    ) async -> RenderedSpeech? {
        let raw: [AVAudioPCMBuffer] = await withCheckedContinuation { continuation in
            let collector = BufferCollector(continuation: continuation)
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    collector.finish()
                    return
                }
                // A zero-length buffer marks the end of the utterance.
                if pcm.frameLength == 0 {
                    collector.finish()
                } else {
                    collector.add(pcm)
                }
            }
        }

        guard let first = raw.first else { return nil }
        guard let target = AVAudioFormat(
            standardFormatWithSampleRate: first.format.sampleRate,
            channels: 1
        ) else { return nil }

        // Already float32 mono — no conversion needed.
        if first.format.commonFormat == .pcmFormatFloat32, first.format.channelCount == 1 {
            return RenderedSpeech(format: first.format, buffers: raw)
        }

        guard let converter = AVAudioConverter(from: first.format, to: target) else { return nil }
        var converted: [AVAudioPCMBuffer] = []
        converted.reserveCapacity(raw.count)

        for source in raw {
            let ratio = target.sampleRate / source.format.sampleRate
            let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
                continue
            }
            let input = SingleBufferInput(source)
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in input.next(status) }
            if error == nil, output.frameLength > 0 { converted.append(output) }
        }

        guard !converted.isEmpty else { return nil }
        return RenderedSpeech(format: target, buffers: converted)
    }
}

/// Feeds exactly one buffer to `AVAudioConverter`, then reports "no more data".
///
/// The converter invokes its input block synchronously, but the block is typed
/// `@Sendable`, so the one-shot state lives in a reference type.
private final class SingleBufferInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var consumed = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if consumed {
            status.pointee = .noDataNow
            return nil
        }
        consumed = true
        status.pointee = .haveData
        return buffer
    }
}

/// Collects rendered buffers and resumes the continuation exactly once.
private final class BufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>?

    init(continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>) {
        self.continuation = continuation
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        buffers.append(buffer)
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let pending = continuation
        continuation = nil
        let result = buffers
        lock.unlock()
        pending?.resume(returning: result)
    }
}

private extension AVSpeechSynthesisVoiceQuality {
    /// Higher is better, for sorting.
    var rank: Int {
        switch self {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default: return 0
        }
    }
}
