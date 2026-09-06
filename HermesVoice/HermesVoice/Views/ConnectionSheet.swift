//  Settings sheet: server connection, language, voice, and activation mode.

import AVFoundation
import SwiftUI

struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var testState: TestState = .untested
    @State private var urlError: String?
    @State private var keyError: String?

    private enum TestState: Equatable {
        case untested
        case testing
        case success
        case failure(String)
    }

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollOrStack(alignment: .leading, spacing: 22) {
                connectionSection(state: state)
                HermesDivider()
                languageSection(state: state)
                HermesDivider()
                behaviourSection(state: state)
            }
            .padding(24)

            footer
        }
        .frame(width: 460)
        .frame(minHeight: 560, maxHeight: 720)
        .background(HermesColors.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("CONFIGURATION")
                .font(HermesFonts.mono(11, weight: .medium))
                .tracking(2)
                .foregroundStyle(HermesColors.primary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func connectionSection(state: AppState) -> some View {
        @Bindable var state = state

        SectionLabel("Server")

        HermesField(
            title: "URL",
            error: urlError,
            content: {
                TextField("http://localhost:8642", text: $state.serverURL)
                    .textFieldStyle(.plain)
                    .font(HermesFonts.mono(13))
                    .foregroundStyle(HermesColors.text)
                    .onChange(of: state.serverURL) { _, _ in
                        testState = .untested
                        urlError = nil
                    }
            }
        )

        HermesField(
            title: "API key",
            error: keyError,
            content: {
                SecureField("sk-…", text: $state.apiKey)
                    .textFieldStyle(.plain)
                    .font(HermesFonts.mono(13))
                    .foregroundStyle(HermesColors.text)
                    .onChange(of: state.apiKey) { _, _ in
                        testState = .untested
                        keyError = nil
                    }
            }
        )

        HStack(spacing: 12) {
            Button(action: testConnection) {
                Text("Test connection")
                    .font(HermesFonts.mono(12))
            }
            .buttonStyle(HermesButtonStyle())
            .disabled(testState == .testing)

            statusIndicator
            Spacer()
        }
    }

    @ViewBuilder
    private func languageSection(state: AppState) -> some View {
        SectionLabel("Language")

        if state.availableLanguages.isEmpty {
            Text("No language on this Mac supports both speech recognition and synthesis.")
                .font(HermesFonts.mono(11))
                .foregroundStyle(HermesColors.error)
        } else {
            Picker(
                "",
                selection: Binding(
                    get: { state.language },
                    set: { state.changeLanguage(to: $0) }
                )
            ) {
                ForEach(state.availableLanguages) { language in
                    HStack {
                        Text(language.pickerLabel)
                        if !language.supportsOnDeviceRecognition {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                    }
                    .tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(HermesFonts.mono(12))

            if !state.language.supportsOnDeviceRecognition {
                HermesNote(
                    icon: "exclamationmark.triangle.fill",
                    tint: HermesColors.error,
                    text: "\(state.language.displayName) is not transcribed on-device, so audio "
                        + "is sent to Apple for recognition."
                )
            }

            voicePicker(state: state)
        }
    }

    @ViewBuilder
    private func voicePicker(state: AppState) -> some View {
        if state.synthesizer.availableVoices.isEmpty {
            HermesNote(
                icon: "speaker.slash.fill",
                tint: HermesColors.error,
                text: "No \(state.language.displayName) voice is installed. Responses will be "
                    + "text-only — add one in System Settings › Accessibility › Spoken Content."
            )
        } else {
            HStack {
                Text("Voice")
                    .font(HermesFonts.mono(11))
                    .foregroundStyle(HermesColors.text.opacity(0.6))
                    .frame(width: 60, alignment: .leading)

                Picker(
                    "",
                    selection: Binding(
                        get: { state.synthesizer.selectedVoiceId ?? "" },
                        set: { state.selectVoice(id: $0.isEmpty ? nil : $0) }
                    )
                ) {
                    ForEach(state.synthesizer.availableVoices, id: \.identifier) { voice in
                        Text(voiceLabel(voice)).tag(voice.identifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(HermesFonts.mono(12))
            }
        }
    }

    @ViewBuilder
    private func behaviourSection(state: AppState) -> some View {
        @Bindable var state = state

        SectionLabel("Activation")

        Picker("", selection: $state.activationMode) {
            ForEach(AppState.ActivationMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .font(HermesFonts.mono(12))

        Text(state.activationMode == .pushToTalk
             ? "Hold the microphone button, or ⌘⇧Space, while you speak."
             : "The app listens continuously and sends when you stop speaking.")
            .font(HermesFonts.mono(10))
            .foregroundStyle(HermesColors.text.opacity(0.45))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Save") { save() }
                .buttonStyle(HermesButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Status

    @ViewBuilder
    private var statusIndicator: some View {
        switch testState {
        case .untested:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…")
                    .font(HermesFonts.mono(11))
                    .foregroundStyle(HermesColors.text.opacity(0.6))
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(HermesFonts.mono(11))
                .foregroundStyle(HermesColors.secondary)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(HermesFonts.mono(11))
                .foregroundStyle(HermesColors.error)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private func testConnection() {
        guard validate() else { return }
        testState = .testing
        Task {
            appState.client.baseURL = appState.serverURL
            appState.client.apiKey = appState.apiKey
            do {
                _ = try await appState.client.checkHealth()
                testState = .success
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }

    private func save() {
        // A failing server should not trap the user in the sheet — save anyway.
        guard validate() else { return }
        Task {
            await appState.connect()
            dismiss()
        }
    }

    private func validate() -> Bool {
        let url = appState.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        urlError = nil
        keyError = nil

        if url.isEmpty {
            urlError = "Enter the URL of your Hermes API server."
        } else if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
            urlError = "The URL must start with http:// or https://"
        } else if HermesClient.endpoint(base: HermesClient.normalizedBase(url), path: "/health") == nil {
            urlError = "That does not look like a valid URL."
        }

        if appState.apiKey.isEmpty {
            keyError = "Enter the API key your server expects."
        }
        return urlError == nil && keyError == nil
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name) · Premium"
        case .enhanced: return "\(voice.name) · Enhanced"
        default: return voice.name
        }
    }
}

// MARK: - Building blocks

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(HermesFonts.mono(10, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(HermesColors.primary.opacity(0.8))
    }
}

private struct HermesField<Content: View>: View {
    let title: String
    let error: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(HermesFonts.mono(10))
                .foregroundStyle(HermesColors.text.opacity(0.5))

            content
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            error == nil ? HermesColors.primary.opacity(0.35) : HermesColors.error,
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if let error {
                Text(error)
                    .font(HermesFonts.mono(10))
                    .foregroundStyle(HermesColors.error)
            }
        }
    }
}

private struct HermesNote: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(tint)
            Text(text)
                .font(HermesFonts.mono(10))
                .foregroundStyle(HermesColors.text.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct HermesDivider: View {
    var body: some View {
        Rectangle()
            .fill(HermesColors.accent)
            .frame(height: 1)
    }
}

struct HermesButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HermesFonts.mono(12))
            .foregroundStyle(prominent ? HermesColors.background : HermesColors.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(prominent ? HermesColors.primary : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(HermesColors.primary.opacity(prominent ? 0 : 0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    ConnectionSheet()
        .environment(AppState(previewing: true))
}
