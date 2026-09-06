//  HUD waveform: a fan of bars around the orb, driven by the real audio spectrum.

import SwiftUI

struct WaveformView: View {
    enum Mode {
        /// Microphone input, shown while listening.
        case input
        /// TTS output, shown while speaking.
        case output

        var tint: Color {
            switch self {
            case .input: return HermesColors.primary
            case .output: return HermesColors.secondary
            }
        }
    }

    let mode: Mode
    /// Spectrum bands in 0...1, newest first. Supplied by `AudioEngine`.
    let bands: [Float]

    /// Radius of the orb the fan wraps around.
    var innerRadius: CGFloat = 122
    /// Arc the bars span, centred on the bottom of the orb.
    var arcDegrees: Double = 190
    /// Longest a bar can grow.
    var maxBarLength: CGFloat = 42

    var body: some View {
        Canvas { context, size in
            guard !bands.isEmpty else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let sweep = arcDegrees * .pi / 180
            // Centre the fan on the bottom of the orb.
            let start = (.pi / 2) - sweep / 2

            for (index, value) in bands.enumerated() {
                let t = bands.count == 1 ? 0.5 : Double(index) / Double(bands.count - 1)
                let angle = start + sweep * t

                // Taper the ends so the fan fades out instead of stopping abruptly.
                let taper = sin(t * .pi)
                let magnitude = CGFloat(value) * CGFloat(taper)
                let length = max(2, magnitude * maxBarLength)

                let cosA = CGFloat(cos(angle))
                let sinA = CGFloat(sin(angle))
                let from = CGPoint(
                    x: center.x + innerRadius * cosA,
                    y: center.y + innerRadius * sinA
                )
                let to = CGPoint(
                    x: center.x + (innerRadius + length) * cosA,
                    y: center.y + (innerRadius + length) * sinA
                )

                var bar = Path()
                bar.move(to: from)
                bar.addLine(to: to)

                let opacity = 0.25 + Double(magnitude) * 0.75
                context.stroke(
                    bar,
                    with: .color(mode.tint.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
        // The bands are already smoothed in the analyser; this softens the fade in/out.
        .animation(.easeOut(duration: 0.08), value: bands)
    }
}

#Preview("Input") {
    WaveformView(
        mode: .input,
        bands: (0..<28).map { Float(abs(sin(Double($0) / 3.2))) * 0.85 }
    )
    .frame(width: 360, height: 360)
    .background(HermesColors.background)
}

#Preview("Output") {
    WaveformView(
        mode: .output,
        bands: (0..<28).map { Float(abs(cos(Double($0) / 2.1))) * 0.7 }
    )
    .frame(width: 360, height: 360)
    .background(HermesColors.background)
}
