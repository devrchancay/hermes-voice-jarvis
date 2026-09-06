//  The central orb: a gradient sphere whose size and colour follow the app state.

import SwiftUI

struct OrbView: View {
    let state: OrbState

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: gradientColors,
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: glowColor.opacity(0.6), radius: 40)
            .overlay(
                Circle()
                    .stroke(glowColor.opacity(0.5), lineWidth: 1)
                    .frame(width: diameter * 1.3, height: diameter * 1.3)
            )
            .animation(.easeInOut(duration: 0.35), value: diameter)
            .animation(.easeInOut(duration: 0.35), value: state)
    }

    // MARK: - Appearance

    private var diameter: CGFloat {
        switch state {
        case .idle: return 120
        case .listening: return 160
        case .thinking: return 140
        case .speaking: return 150
        case .error: return 100
        }
    }

    private var gradientColors: [Color] {
        switch state {
        case .idle:
            return [HermesColors.primary.opacity(0.5), HermesColors.primary.opacity(0.05)]
        case .listening:
            return [HermesColors.secondary, HermesColors.primary.opacity(0.2)]
        case .thinking:
            return [HermesColors.secondary, HermesColors.secondary.opacity(0.15)]
        case .speaking:
            return [HermesColors.secondary, HermesColors.primary.opacity(0.3)]
        case .error:
            return [HermesColors.error, HermesColors.error.opacity(0.1)]
        }
    }

    private var glowColor: Color {
        switch state {
        case .error: return HermesColors.error
        case .thinking, .speaking: return HermesColors.secondary
        default: return HermesColors.primary
        }
    }
}

#Preview("Orb states") {
    HStack(spacing: 40) {
        ForEach(
            [OrbState.idle, .listening, .thinking, .speaking, .error("x")],
            id: \.label
        ) { state in
            VStack {
                OrbView(state: state)
                Text(state.label)
                    .font(HermesFonts.mono(9))
                    .foregroundStyle(HermesColors.text.opacity(0.5))
            }
            .frame(width: 200, height: 240)
        }
    }
    .padding(40)
    .background(HermesColors.background)
}
