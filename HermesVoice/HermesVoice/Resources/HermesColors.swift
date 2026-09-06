//  The J.A.R.V.I.S.-inspired colour palette shared by every view.

import SwiftUI

/// Colour palette for the whole app. Values come from SPEC.md.
enum HermesColors {
    /// Pure black canvas the HUD is drawn on.
    static let background = Color.black
    /// Electric blue — the resting accent.
    static let primary = Color(hex: 0x00A8FF)
    /// Cyan — energy, activity, the "thinking" end of the spectrum.
    static let secondary = Color(hex: 0x00F5FF)
    /// Faint white used for grid lines and dividers.
    static let accent = Color.white.opacity(0.15)
    /// Primary text colour.
    static let text = Color.white
    /// Orange — errors and warnings.
    static let error = Color(hex: 0xFF6B35)
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
