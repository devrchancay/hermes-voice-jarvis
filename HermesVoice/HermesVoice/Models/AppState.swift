//  Central observable state coordinating networking, speech, and the HUD.

import AVFoundation
import Foundation
import Observation
import os

// MARK: - Orb state

/// Visual state of the orb; maps 1:1 onto the states in SPEC.md.
enum OrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error(String)

    var label: String {
        switch self {
        case .idle: return "READY"
        case .listening: return "LISTENING"
        case .thinking: return "PROCESSING"
        case .speaking: return "SPEAKING"
        case .error: return "ERROR"
        }
    }

    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }

    /// Read by VoiceOver in place of the orb, which is purely decorative.
    var spokenStatus: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .error(let message): return "Error. \(message)"
        }
    }
}

// MARK: - App state

@MainActor
@Observable
final class AppState {

    // MARK: Runtime state

    private(set) var orbState: OrbState = .idle
    private(set) var messages: [Message] = []
    /// What the user is saying right now.
    var currentTranscript: String = ""
    /// What the assistant is answering right now.
    private(set) var currentResponse: String = ""
    private(set) var isConnected: Bool = false
    /// True while passively waiting for speech in continuous mode.
    private(set) var isPassivelyListening: Bool = false
    /// Set when the language has no installed voice — the app stays text-only.
    private(set) var voiceUnavailableNotice: String?

    // MARK: Configuration

    var serverURL: String {
        didSet { Defaults.serverURL = serverURL }
    }
    var apiKey: String {
        didSet { Keychain.set(apiKey, account: Self.keychainAccount) }
    }
    private(set) var language: SpeechLanguage
    private(set) var voiceIdsByLanguage: [String: String]
    var customSystemPrompt: String? {
        didSet { Defaults.customSystemPrompt = customSystemPrompt }
    }
    var activationMode: ActivationMode {
        didSet {
            Defaults.activationMode = activationMode.rawValue
            activationModeChanged()
        }
    }

    enum ActivationMode: String, CaseIterable, Identifiable {
        case pushToTalk
        case continuous

        var id: String { rawValue }
        var label: String {
            switch self {
            case .pushToTalk: return "Push to talk"
            case .continuous: return "Continuous"
            }
        }
    }

    /// True on first launch, when the connection sheet should open by itself.
    var needsConfiguration: Bool { serverURL.isEmpty }

    /// Languages offered in the settings picker.
    let availableLanguages: [SpeechLanguage]

    // MARK: Components

    let client: HermesClient
    let audioEngine: AudioEngine
    let recognizer: SpeechRecognizer
    let synthesizer: SpeechSynthesizer

    // MARK: Private

    private var streamTask: Task<Void, Never>?
    private var vad = VoiceActivityDetector()
    private var levelObserver: Task<Void, Never>?
    private var interruptionArmedAt: Date?
    private var errorResetTask: Task<Void, Never>?

    /// True in previews and unit tests: no audio is played and no key is read.
    private let isPreviewing: Bool

    private static let keychainAccount = "api-key"
    private static let logger = Logger(subsystem: "com.desarol.hermes-voice", category: "AppState")

    /// Default system prompt. Written in English on purpose: it instructs the model,
    /// it is not user-facing copy. The reply language is appended separately.
    static let defaultPromptTemplate = """
        You are Hermes, a voice assistant. Answer concisely and naturally, the way you \
        would in a spoken conversation. Keep responses to 2-3 sentences unless more \
        detail is requested. Your output is read aloud by a speech synthesizer, so \
        write plain prose: no markdown, no bullet lists, no code blocks, no emoji.
        """

    /// How many turns to keep before trimming, so the context window never overflows.
    private let maxStoredTurns = 40

    // MARK: Init

    init(previewing: Bool = false) {
        let engine = AudioEngine()
        let resolved = SpeechLanguageCatalog.language(withID: Defaults.languageID)
            ?? SpeechLanguage(
                id: "en-US",
                displayName: "English (United States)",
                endonym: "English (United States)",
                englishName: "English",
                supportsOnDeviceRecognition: false,
                hasInstalledVoice: false
            )

        self.isPreviewing = previewing
        self.audioEngine = engine
        self.language = resolved
        self.availableLanguages = SpeechLanguageCatalog.available()
        self.serverURL = Defaults.serverURL
        self.apiKey = previewing ? "" : (Keychain.get(account: Self.keychainAccount) ?? "")
        self.voiceIdsByLanguage = Defaults.voiceIdsByLanguage
        self.customSystemPrompt = Defaults.customSystemPrompt
        self.activationMode = ActivationMode(rawValue: Defaults.activationMode) ?? .pushToTalk

        self.client = HermesClient(baseURL: Defaults.serverURL, apiKey: "")
        self.recognizer = SpeechRecognizer(locale: resolved.locale, audioEngine: engine)
        self.synthesizer = SpeechSynthesizer(audioEngine: engine)

        self.client.apiKey = self.apiKey
        self.synthesizer.selectedVoiceId = voiceIdsByLanguage[resolved.id]
        self.synthesizer.loadVoices(language: resolved.id)
        self.synthesizer.onFinishedSpeaking = { [weak self] in
            self?.handleSpeechFinished()
        }
        refreshVoiceNotice()
    }

    // MARK: - Connection

    func connect() async {
        client.baseURL = serverURL
        client.apiKey = apiKey

        guard !serverURL.isEmpty else {
            setError("Set a server URL to get started.")
            return
        }

        do {
            _ = try await client.checkHealth()
            isConnected = true
            setOrbState(.idle)
            Self.logger.info("Connected to \(self.serverURL, privacy: .public)")
            if activationMode == .continuous { startPassiveListening() }
        } catch {
            isConnected = false
            setError(error.localizedDescription)
        }
    }

    func disconnect() {
        cancelCurrentRequest()
        stopPassiveListening()
        isConnected = false
        client.isConnected = false
        setOrbState(.idle)
    }

    // MARK: - Language

    /// Switches language mid-session, keeping the conversation history.
    func changeLanguage(to newLanguage: SpeechLanguage) {
        guard newLanguage.id != language.id else { return }

        synthesizer.stop()
        recognizer.abort()

        do {
            try recognizer.setLocale(newLanguage.locale)
        } catch {
            // Keep the previous language rather than leaving the app unable to listen.
            setError("Could not switch to \(newLanguage.displayName): \(error.localizedDescription)")
            return
        }

        language = newLanguage
        Defaults.languageID = newLanguage.id

        synthesizer.selectedVoiceId = voiceIdsByLanguage[newLanguage.id]
        synthesizer.loadVoices(language: newLanguage.id)
        refreshVoiceNotice()

        setOrbState(.idle)
        if activationMode == .continuous, isConnected { startPassiveListening() }
        Self.logger.info("Language switched to \(newLanguage.id, privacy: .public)")
    }

    /// Records the chosen voice for the current language.
    func selectVoice(id: String?) {
        synthesizer.selectedVoiceId = id
        if let id {
            voiceIdsByLanguage[language.id] = id
        } else {
            voiceIdsByLanguage.removeValue(forKey: language.id)
        }
        Defaults.voiceIdsByLanguage = voiceIdsByLanguage
    }

    private func refreshVoiceNotice() {
        voiceUnavailableNotice = synthesizer.hasVoice
            ? nil
            : "No \(language.displayName) voice is installed. Responses will be text-only — "
                + "add one in System Settings › Accessibility › Spoken Content."
    }

    // MARK: - System prompt

    /// Built fresh on every request, so a language switch applies on the next turn.
    func systemPrompt() -> String {
        let base = customSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = (base?.isEmpty == false) ? base! : Self.defaultPromptTemplate
        return """
            \(template)

            Always reply in \(language.englishName), regardless of the language of these \
            instructions.
            """
    }

    // MARK: - Voice loop

    func startListening() {
        guard orbState != .listening else { return }

        // Speaking over the assistant is an interruption, not a fresh turn.
        if orbState == .speaking {
            interruptSpeech(reason: .userPressedTalk)
            return
        }

        cancelErrorReset()
        stopPassiveListening()
        currentTranscript = ""
        currentResponse = ""

        Task {
            guard await ensurePermissions() else { return }
            do {
                try recognizer.startListening()
                setOrbState(.listening)
                observeTranscript()
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    func stopListeningAndSend() async {
        guard orbState == .listening else { return }

        let text = recognizer.stopListening()
        currentTranscript = text

        guard !text.isEmpty else {
            setOrbState(.idle)
            resumePassiveListeningIfNeeded()
            return
        }

        await send(text)
    }

    /// Sends a turn and streams the reply. Also used by the text fallback path.
    func send(_ text: String) async {
        guard isConnected else {
            setError("Not connected. Check the server URL in settings.")
            return
        }

        appendMessage(Message(role: .user, content: text))
        currentResponse = ""
        setOrbState(.thinking)

        let prompt = systemPrompt()
        let history = messages
        if !isPreviewing { synthesizer.speakStreaming() }

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            var accumulated = ""
            var sawFirstToken = false

            do {
                for try await token in client.sendMessage(messages: history, systemPrompt: prompt) {
                    if Task.isCancelled { break }
                    if !sawFirstToken {
                        sawFirstToken = true
                        self.setOrbState(.speaking)
                        self.armInterruptionDetection()
                    }
                    accumulated += token
                    self.currentResponse = accumulated
                    if !self.isPreviewing { self.synthesizer.appendToken(token) }
                }
            } catch {
                self.synthesizer.stop()
                self.disarmInterruptionDetection()

                // Cancellation surfaces here as a thrown error. It is not a failure:
                // the caller already decided what to keep, and showing an error
                // banner for a deliberate stop would be wrong.
                guard !Task.isCancelled else { return }

                if !accumulated.isEmpty {
                    self.appendMessage(Message(role: .assistant, content: accumulated))
                }
                self.setError(error.localizedDescription)
                return
            }

            // A cancelled turn must not append anything. Whoever cancelled has already
            // decided what to keep: interruptSpeech stores the partial answer itself,
            // and clearConversation wants the history gone. Appending here would
            // resurrect a message into a cleared conversation, or duplicate the one
            // interruptSpeech just stored.
            guard !Task.isCancelled else { return }

            if !accumulated.isEmpty {
                self.appendMessage(Message(role: .assistant, content: accumulated))
            }
            if !self.isPreviewing { self.synthesizer.finishStreaming() }

            // Nothing to speak (previewing, no voice installed, or an empty reply).
            if self.isPreviewing || !self.synthesizer.hasVoice || accumulated.isEmpty {
                self.handleSpeechFinished()
            }
        }
    }

    func cancelCurrentRequest() {
        streamTask?.cancel()
        streamTask = nil
        client.cancel()
        synthesizer.stop()
        recognizer.abort()
        disarmInterruptionDetection()
        setOrbState(.idle)
        resumePassiveListeningIfNeeded()
    }

    func clearConversation() {
        cancelCurrentRequest()
        messages.removeAll()
        currentTranscript = ""
        currentResponse = ""
    }

    // MARK: - Interruptions

    private enum InterruptionReason {
        case userSpoke
        case userPressedTalk
    }

    /// Starts watching the microphone so the user can talk over the assistant.
    ///
    /// Requires an already-granted microphone permission: starting the engine without
    /// one blocks in CoreAudio, and barge-in is not worth a permission prompt in the
    /// middle of a reply.
    private func armInterruptionDetection() {
        guard !isPreviewing else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        guard activationMode == .continuous || recognizer.state != .listening else { return }
        guard !audioEngine.isInputRunning else { return }
        do {
            try audioEngine.startInput()
            interruptionArmedAt = Date()
            observeInterruptions()
        } catch {
            // Not fatal: the user can still interrupt with the mic button.
            Self.logger.notice("Interruption detection unavailable: \(error.localizedDescription)")
        }
    }

    private func disarmInterruptionDetection() {
        interruptionArmedAt = nil
        if audioEngine.isInputRunning, recognizer.state != .listening {
            audioEngine.stopInput()
        }
    }

    private func interruptSpeech(reason: InterruptionReason) {
        Self.logger.info("Speech interrupted")
        streamTask?.cancel()
        streamTask = nil
        client.cancel()

        // Keep whatever was said, marked as cut short.
        let partial = currentResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty, messages.last?.role != .assistant {
            appendMessage(Message(role: .assistant, content: partial + "…"))
        }

        synthesizer.stop()
        disarmInterruptionDetection()

        currentTranscript = ""
        currentResponse = partial.isEmpty ? "" : partial + "…"

        // Straight from speaking to listening, without passing through idle.
        Task {
            guard await ensurePermissions() else { return }
            do {
                try recognizer.startListening()
                setOrbState(.listening)
                observeTranscript()
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    // MARK: - Continuous mode

    private func activationModeChanged() {
        switch activationMode {
        case .pushToTalk:
            stopPassiveListening()
        case .continuous:
            if isConnected, orbState == .idle { startPassiveListening() }
        }
    }

    private func startPassiveListening() {
        guard activationMode == .continuous, !isPassivelyListening else { return }
        Task {
            guard await ensurePermissions() else { return }
            do {
                try audioEngine.startInput()
                vad.reset()
                isPassivelyListening = true
                observeVoiceActivity()
                Self.logger.info("Passive listening started")
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func stopPassiveListening() {
        guard isPassivelyListening else { return }
        isPassivelyListening = false
        levelObserver?.cancel()
        levelObserver = nil
        vad.reset()
        if recognizer.state != .listening { audioEngine.stopInput() }
    }

    private func resumePassiveListeningIfNeeded() {
        guard activationMode == .continuous, isConnected else { return }
        startPassiveListening()
    }

    // MARK: - Observation loops

    /// Mirrors the recogniser's live transcript into the HUD.
    private func observeTranscript() {
        Task { [weak self] in
            while let self, self.recognizer.state == .listening, !Task.isCancelled {
                self.currentTranscript = self.recognizer.transcript
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// Watches microphone level while the assistant speaks, to detect barge-in.
    private func observeInterruptions() {
        Task { [weak self] in
            while let self, self.orbState == .speaking, !Task.isCancelled {
                // Ignore the first moment so the speaker's own onset cannot self-trigger.
                if let armed = self.interruptionArmedAt,
                   Date().timeIntervalSince(armed) > 0.4 {
                    let speech = self.audioEngine.inputLevel
                    let output = self.audioEngine.outputLevel
                    // Raise the bar in proportion to our own output: the mic hears the
                    // speaker, so a fixed threshold would make the app interrupt itself.
                    let threshold = 0.22 + output * 0.5
                    if speech > threshold {
                        if self.interruptionSustained() {
                            self.interruptSpeech(reason: .userSpoke)
                            return
                        }
                    } else {
                        self.interruptionCandidateSince = nil
                    }
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private var interruptionCandidateSince: Date?

    /// Requires the level to stay high for 300 ms, so a cough does not cut speech off.
    private func interruptionSustained() -> Bool {
        let now = Date()
        guard let since = interruptionCandidateSince else {
            interruptionCandidateSince = now
            return false
        }
        return now.timeIntervalSince(since) >= 0.3
    }

    /// Drives hands-free mode from the microphone level.
    private func observeVoiceActivity() {
        levelObserver?.cancel()
        levelObserver = Task { [weak self] in
            while let self, self.isPassivelyListening, !Task.isCancelled {
                let level = self.audioEngine.inputLevel
                switch self.vad.process(level: level) {
                case .speechStarted where self.orbState == .idle:
                    self.beginContinuousTurn()
                case .speechEnded where self.orbState == .listening:
                    await self.stopListeningAndSend()
                default:
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func beginContinuousTurn() {
        currentTranscript = ""
        currentResponse = ""
        do {
            try recognizer.startListening()
            setOrbState(.listening)
            observeTranscript()
        } catch {
            setError(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func ensurePermissions() async -> Bool {
        let granted = await recognizer.requestPermission()
        if !granted {
            setError(recognizer.state.deniedMessage ?? "Microphone permission is required.")
        }
        return granted
    }

    private func handleSpeechFinished() {
        disarmInterruptionDetection()
        guard orbState == .speaking || orbState == .thinking else { return }
        setOrbState(.idle)
        resumePassiveListeningIfNeeded()
    }

    private func appendMessage(_ message: Message) {
        messages.append(message)
        // Trim the oldest turns so long sessions do not blow the context window.
        if messages.count > maxStoredTurns {
            messages.removeFirst(messages.count - maxStoredTurns)
        }
    }

    private func setOrbState(_ new: OrbState) {
        orbState = new
    }

    private func setError(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
        setOrbState(.error(message))
        cancelErrorReset()
        // The orb returns to idle on its own, as the spec's error state describes.
        errorResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            if case .error = self.orbState {
                self.setOrbState(.idle)
                self.resumePassiveListeningIfNeeded()
            }
        }
    }

    private func cancelErrorReset() {
        errorResetTask?.cancel()
        errorResetTask = nil
    }

    // MARK: - Test seams

    /// Swaps the client's transport so tests can stub the network.
    func replaceClientSessionForTesting(_ session: URLSession) {
        client.replaceSession(session)
    }

    /// Waits for the current turn to settle. Returns early rather than hanging.
    func waitForIdleForTesting(allowError: Bool = false, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if orbState == .idle { return }
            if allowError, orbState.errorMessage != nil { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - Defaults

/// Typed access to UserDefaults. The API key deliberately lives in the Keychain.
private enum Defaults {
    // UserDefaults is thread-safe but predates Sendable, so the guarantee is asserted.
    private static var store: UserDefaults { .standard }

    static var serverURL: String {
        get { store.string(forKey: "serverURL") ?? "" }
        set { store.set(newValue, forKey: "serverURL") }
    }

    static var languageID: String? {
        get { store.string(forKey: "languageID") }
        set { store.set(newValue, forKey: "languageID") }
    }

    static var voiceIdsByLanguage: [String: String] {
        get { store.dictionary(forKey: "voiceIdsByLanguage") as? [String: String] ?? [:] }
        set { store.set(newValue, forKey: "voiceIdsByLanguage") }
    }

    static var customSystemPrompt: String? {
        get { store.string(forKey: "customSystemPrompt") }
        set { store.set(newValue, forKey: "customSystemPrompt") }
    }

    static var activationMode: String {
        get { store.string(forKey: "activationMode") ?? AppState.ActivationMode.pushToTalk.rawValue }
        set { store.set(newValue, forKey: "activationMode") }
    }
}

private extension SpeechRecognizerState {
    var deniedMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

// MARK: - Preview support

#if DEBUG
extension AppState {
    /// Builds a state populated for SwiftUI previews and screenshot rendering.
    ///
    /// Debug-only: the setters it reaches are `private(set)` precisely so nothing in
    /// the shipping app can drive the HUD into an inconsistent state.
    static func preview(
        orbState: OrbState = .idle,
        transcript: String = "",
        response: String = "",
        messages: [Message] = [],
        connected: Bool = true,
        language: SpeechLanguage? = nil,
        activationMode: ActivationMode = .pushToTalk
    ) -> AppState {
        let state = AppState(previewing: true)
        state.orbState = orbState
        state.currentTranscript = transcript
        state.currentResponse = response
        state.messages = messages
        state.isConnected = connected
        state.serverURL = "http://localhost:8642"
        state.activationMode = activationMode
        if let language { state.language = language }
        return state
    }
}
#endif
