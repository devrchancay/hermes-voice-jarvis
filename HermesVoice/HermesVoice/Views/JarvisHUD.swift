//  The main screen: status bar, transcript, orb, response, and the two controls.

import SwiftUI

struct JarvisHUD: View {
    @Environment(AppState.self) private var appState

    @Binding var showingSettings: Bool
    @State private var isHoldingMic = false

    var body: some View {
        ZStack {
            HermesColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer(minLength: 8)

                UserTranscriptView(text: appState.currentTranscript)
                    .padding(.horizontal, 36)
                    .frame(height: 120)

                Spacer(minLength: 12)

                OrbView(state: appState.orbState)

                Spacer(minLength: 12)

                AssistantResponseView(
                    text: appState.currentResponse,
                    isStreaming: appState.orbState == .speaking
                )
                .padding(.horizontal, 36)
                .frame(height: 140)

                Spacer(minLength: 8)

                controls
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
            }
        }
        .overlay(alignment: .bottom) { errorBanner }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(appState.isConnected ? HermesColors.secondary : HermesColors.text.opacity(0.25))
                    .frame(width: 5, height: 5)
                Text(appState.isConnected ? appState.orbState.label : "OFFLINE")
                    .font(HermesFonts.mono(9, weight: .medium))
                    .tracking(1.8)
                    .foregroundStyle(HermesColors.primary.opacity(0.8))
            }

            Spacer()

            if appState.activationMode == .continuous {
                Image(systemName: "waveform")
                    .font(.system(size: 9))
                    .foregroundStyle(
                        appState.isPassivelyListening
                            ? HermesColors.secondary.opacity(0.8)
                            : HermesColors.text.opacity(0.25)
                    )
                    .help("Continuous listening")
            }

            Text(appState.language.id.uppercased())
                .font(HermesFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(HermesColors.text.opacity(0.35))
                .padding(.leading, 10)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(HermesFonts.mono(9))
                    .foregroundStyle(HermesColors.text.opacity(0.35))
                    .padding(.leading, 10)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            CircleButton(icon: "gearshape", size: 38) {
                showingSettings = true
            }
            .help("Settings")

            Spacer()

            micButton

            Spacer()

            CircleButton(
                icon: "trash",
                size: 38,
                tint: appState.messages.isEmpty
                    ? HermesColors.text.opacity(0.2)
                    : HermesColors.primary
            ) {
                appState.clearConversation()
            }
            .disabled(appState.messages.isEmpty)
            .help("Clear conversation")
        }
    }

    private var micButton: some View {
        let listening = appState.orbState == .listening
        let continuous = appState.activationMode == .continuous

        return Button {
            // In continuous mode the button toggles the mode rather than a single turn.
            if continuous {
                appState.activationMode = .pushToTalk
            }
        } label: {
            ZStack {
                Circle()
                    .fill(listening ? HermesColors.primary.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 62, height: 62)
                Circle()
                    .stroke(
                        listening ? HermesColors.secondary : HermesColors.primary.opacity(0.5),
                        lineWidth: 1.5
                    )
                    .frame(width: 62, height: 62)
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(listening ? HermesColors.secondary : HermesColors.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHoldingMic ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: isHoldingMic)
        .help(continuous ? "Switch to push-to-talk" : "Hold to talk (⌘⇧Space)")
        .simultaneousGesture(pushToTalkGesture(enabled: !continuous))
    }

    /// Press to start listening, release to send — the spec's push-to-talk behaviour.
    private func pushToTalkGesture(enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard enabled, !isHoldingMic else { return }
                isHoldingMic = true
                appState.startListening()
            }
            .onEnded { _ in
                guard enabled, isHoldingMic else { return }
                isHoldingMic = false
                Task { await appState.stopListeningAndSend() }
            }
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let message = appState.orbState.errorMessage {
            Text(message)
                .font(HermesFonts.mono(11))
                .foregroundStyle(HermesColors.error)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(HermesColors.error.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 22)
                .padding(.bottom, 92)
                .transition(.opacity)
        } else if let notice = appState.voiceUnavailableNotice {
            Text(notice)
                .font(HermesFonts.mono(10))
                .foregroundStyle(HermesColors.text.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .padding(.bottom, 92)
        }
    }
}

// MARK: - Circle button

struct CircleButton: View {
    let icon: String
    var size: CGFloat = 38
    var tint: Color = HermesColors.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: size, height: size)
                Circle()
                    .stroke(tint.opacity(0.35), lineWidth: 1)
                    .frame(width: size, height: size)
                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .light))
                    .foregroundStyle(tint)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    JarvisHUD(showingSettings: .constant(false))
        .environment(AppState(previewing: true))
        .frame(width: 520, height: 760)
}
