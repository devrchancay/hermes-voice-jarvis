//  The two text areas of the HUD: the user's transcript above the orb, the reply below.

import SwiftUI

// MARK: - User transcript

/// What the user is saying, shown above the orb.
struct UserTranscriptView: View {
    let text: String
    /// True while the microphone is open. Once it closes, the line fades away.
    var isLive: Bool = false

    @State private var visible = false
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("▶")
                .font(HermesFonts.mono(8))
                .foregroundStyle(HermesColors.primary.opacity(isLive ? 0.9 : 0.3))
                .opacity(text.isEmpty ? 0 : 1)

            Text(text)
                .font(HermesFonts.mono(15, weight: .light))
                .foregroundStyle(HermesColors.text.opacity(0.8))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: visible)
        .animation(.easeInOut(duration: 0.15), value: text)
        .onAppear {
            visible = !text.isEmpty
            scheduleFade()
        }
        .onChange(of: text) { _, newValue in
            if !newValue.isEmpty { visible = true }
            scheduleFade()
        }
        .onChange(of: isLive) { _, _ in scheduleFade() }
    }

    /// Once the turn is sent the question lingers briefly, then clears, so the screen
    /// is not left holding a stale line while the answer is read out.
    private func scheduleFade() {
        fadeTask?.cancel()
        guard !isLive, !text.isEmpty else { return }
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}

// MARK: - Assistant response

/// Hermes' reply, shown below the orb and scrolled as tokens arrive.
struct AssistantResponseView: View {
    let text: String
    let isStreaming: Bool

    @Environment(\.isStaticSnapshot) private var isStaticSnapshot
    @State private var cursorOn = true

    var body: some View {
        Group {
            if isStaticSnapshot {
                responseText
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        responseText.id("response")
                    }
                    .scrollIndicators(.never)
                    // Keep the newest tokens in view as they stream in.
                    .onChange(of: text) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("response", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .opacity(text.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: text.isEmpty)
        .task(id: isStreaming) {
            guard isStreaming else {
                cursorOn = false
                return
            }
            while !Task.isCancelled {
                cursorOn.toggle()
                try? await Task.sleep(for: .milliseconds(530))
            }
        }
    }

    private var responseText: some View {
        (Text(text) + cursor)
            .font(HermesFonts.mono(16))
            .foregroundStyle(HermesColors.text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .top)
            .textSelection(.enabled)
    }

    /// The cursor glyph is always in the string and only changes colour, so blinking
    /// never reflows the paragraph.
    private var cursor: Text {
        let showing = isStreaming && cursorOn && !isStaticSnapshot
        return Text(" ▌").foregroundColor(showing ? HermesColors.secondary : .clear)
    }
}

#Preview("Live") {
    VStack(spacing: 30) {
        UserTranscriptView(text: "What is the weather like today?", isLive: true)
        AssistantResponseView(
            text: "It is sunny and about 24 degrees.",
            isStreaming: true
        )
        .frame(height: 120)
    }
    .padding(40)
    .frame(width: 460, height: 320)
    .background(HermesColors.background)
}

#Preview("Settled") {
    VStack(spacing: 30) {
        UserTranscriptView(text: "What is the weather like today?", isLive: false)
        AssistantResponseView(
            text: "It is sunny and about 24 degrees.",
            isStreaming: false
        )
        .frame(height: 120)
    }
    .padding(40)
    .frame(width: 460, height: 320)
    .background(HermesColors.background)
}
