//  The J.A.R.V.I.S.-inspired colour palette shared by every view.

import SwiftUI

/// Colour palette for the whole app. Values come from SPEC.md.
enum HermesColors {
    /// Pure black canvas the HUD is drawn on.
    static let background = Color.black
    /// Electric blue — the resting accent.
    static let primaryHex: UInt32 = 0x00A8FF
    static let primary = Color(hex: primaryHex)
    /// Cyan — energy, activity, the "thinking" end of the spectrum.
    static let secondaryHex: UInt32 = 0x00F5FF
    static let secondary = Color(hex: secondaryHex)
    /// Faint white used for grid lines and dividers.
    static let accent = Color.white.opacity(0.15)
    /// Primary text colour.
    static let text = Color.white
    /// Orange — errors and warnings.
    static let errorHex: UInt32 = 0xFF6B35
    static let error = Color(hex: errorHex)

    /// Linear blend between two hex literals, `t` running 0 (from) to 1 (to).
    ///
    /// Used to shade depth gradients without `Color.mix`, which needs macOS 15.
    static func blend(_ from: UInt32, _ to: UInt32, _ t: Double, opacity: Double = 1) -> Color {
        let amount = max(0, min(1, t))
        func channel(_ shift: UInt32) -> Double {
            let a = Double((from >> shift) & 0xFF)
            let b = Double((to >> shift) & 0xFF)
            return (a + (b - a) * amount) / 255
        }
        return Color(
            .sRGB,
            red: channel(16),
            green: channel(8),
            blue: channel(0),
            opacity: opacity
        )
    }
}

extension Color {
    /// Builds a colour from a 24-bit RGB literal, e.g. `Color(hex: 0x00A8FF)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Monospace fonts used across the HUD.
enum HermesFonts {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
