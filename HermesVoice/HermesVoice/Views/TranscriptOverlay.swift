//  The two text areas of the HUD: the user's transcript above the orb, the reply below.

import SwiftUI

// MARK: - User transcript

/// What the user is saying, shown above the orb.
struct UserTranscriptView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HermesFonts.mono(15, weight: .light))
            .foregroundStyle(HermesColors.text.opacity(0.8))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: .infinity)
            .opacity(text.isEmpty ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: text)
    }
}

// MARK: - Assistant response

/// Hermes' reply, shown below the orb and scrolled as tokens arrive.
struct AssistantResponseView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(HermesFonts.mono(16))
                    .foregroundStyle(HermesColors.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .textSelection(.enabled)
                    .id("response")
            }
            .scrollIndicators(.never)
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("response", anchor: .bottom)
                }
            }
        }
        .opacity(text.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: text.isEmpty)
    }
}

#Preview("Transcript areas") {
    VStack(spacing: 30) {
        UserTranscriptView(text: "What is the weather like today?")
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
