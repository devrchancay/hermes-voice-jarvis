//  Slide-in panel listing the current conversation, styled to match the HUD.

import SwiftUI

struct ConversationHistoryView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool

    @Environment(\.isStaticSnapshot) private var isStaticSnapshot

    @State private var confirmingClear = false
    @State private var copiedMessageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            HermesDivider()
            transcript
            HermesDivider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HermesColors.background.opacity(0.94))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TRANSCRIPT")
                .font(HermesFonts.mono(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(HermesColors.primary.opacity(0.8))

            Spacer()

            Text("\(appState.messages.count)")
                .font(HermesFonts.mono(10))
                .foregroundStyle(HermesColors.text.opacity(0.35))

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HermesColors.text.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .help("Close")
            .accessibilityLabel("Close history")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Messages

    @ViewBuilder
    private var transcript: some View {
        if isStaticSnapshot {
            rows.padding(16)
            Spacer(minLength: 0)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    rows.padding(16)
                }
                .scrollIndicators(.automatic)
                // Follow the newest turn, but only when one arrives — the user stays
                // free to scroll back while the assistant is still talking.
                .onChange(of: appState.messages.count) { _, _ in
                    guard let last = appState.messages.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.messages.isEmpty {
                Text("Nothing yet. Hold the microphone button and say something.")
                    .font(HermesFonts.mono(11))
                    .foregroundStyle(HermesColors.text.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }

            ForEach(appState.messages) { message in
                MessageRow(
                    message: message,
                    justCopied: copiedMessageID == message.id,
                    onCopy: { copy(message) }
                )
                .id(message.id)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if confirmingClear {
                Text("Clear everything?")
                    .font(HermesFonts.mono(10))
                    .foregroundStyle(HermesColors.text.opacity(0.6))
                Spacer()
                Button("Cancel") { confirmingClear = false }
                    .buttonStyle(HermesButtonStyle())
                Button("Clear") {
                    appState.clearConversation()
                    confirmingClear = false
                }
                .buttonStyle(HermesButtonStyle(prominent: true))
            } else {
                Spacer()
                Button("Clear") { confirmingClear = true }
                    .buttonStyle(HermesButtonStyle())
                    .disabled(appState.messages.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.15), value: confirmingClear)
    }

    private func copy(_ message: Message) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if copiedMessageID == message.id { copiedMessageID = nil }
        }
    }
}

// MARK: - Row

private struct MessageRow: View {
    let message: Message
    let justCopied: Bool
    let onCopy: () -> Void

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(message.content)
                .font(HermesFonts.mono(13))
                .foregroundStyle(HermesColors.text.opacity(isUser ? 0.9 : 1))
                .multilineTextAlignment(isUser ? .trailing : .leading)
                .padding(.horizontal, isUser ? 10 : 0)
                .padding(.vertical, isUser ? 7 : 0)
                .background(
                    isUser
                        ? AnyShapeStyle(HermesColors.primary.opacity(0.12))
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .textSelection(.enabled)

            HStack(spacing: 6) {
                if justCopied {
                    Text("copied")
                        .font(HermesFonts.mono(9))
                        .foregroundStyle(HermesColors.secondary)
                }
                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(HermesFonts.mono(9))
                    .foregroundStyle(HermesColors.text.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .help("Click to copy")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "Hermes"): \(message.content)")
        .accessibilityHint("Copies this message")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ConversationHistoryView(isPresented: .constant(true))
        .environment(
            AppState.preview(messages: [
                Message(role: .user, content: "What can you do?"),
                Message(
                    role: .assistant,
                    content: "I listen on-device and read Hermes' reply back out loud."
                ),
            ])
        )
        .frame(width: 320, height: 500)
}
