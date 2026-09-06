//  The central orb, drawn in Canvas: glow, ring, orbiting particles, and ripples.

import SwiftUI

struct OrbView: View {
    let state: OrbState
    /// Live microphone or TTS level, 0...1, used to modulate the animation.
    var audioLevel: Float = 0

    /// Fixed timestamp for previews and screenshots, so renders are deterministic.
    var frozenTime: Double?

    var body: some View {
        if let frozenTime {
            Canvas { context, size in
                draw(context: context, size: size, time: frozenTime)
            }
            .frame(width: canvasSide, height: canvasSide)
        } else {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    draw(context: context, size: size, time: time)
                }
                .frame(width: canvasSide, height: canvasSide)
            }
        }
    }

    // MARK: - Geometry

    /// Room for the largest glow and the widest ripple.
    private var canvasSide: CGFloat { 360 }

    private var baseRadius: CGFloat {
        switch state {
        case .idle: return 60
        case .listening: return 80
        case .thinking: return 70
        case .speaking: return 75
        case .error: return 50
        }
    }

    // MARK: - Palette

    private var coreColor: Color {
        switch state {
        case .error: return HermesColors.error
        case .thinking, .speaking: return HermesColors.secondary
        case .listening: return HermesColors.secondary
        case .idle: return HermesColors.primary
        }
    }

    private var edgeColor: Color {
        switch state {
        case .error: return HermesColors.error
        case .thinking: return HermesColors.secondary
        default: return HermesColors.primary
        }
    }

    // MARK: - Drawing

    private func draw(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let level = CGFloat(max(0, min(1, audioLevel)))

        let pulse = pulseScale(time: time)
        let radius = baseRadius * pulse * (1 + level * 0.18)
        let intensity = errorFlicker(time: time)

        drawGlow(context, center: center, radius: radius, intensity: intensity)

        if case .speaking = state {
            drawRipples(context, center: center, radius: radius, time: time, level: level)
        }

        drawCore(context, center: center, radius: radius, time: time, level: level,
                 intensity: intensity)
        drawRing(context, center: center, radius: radius, time: time, intensity: intensity)

        if case .thinking = state {
            drawParticles(context, center: center, radius: radius, time: time)
        }
    }

    /// Slow breath at rest, fast pulse while thinking.
    private func pulseScale(time: Double) -> CGFloat {
        switch state {
        case .idle:
            return 1 + 0.03 * CGFloat(sin(time * 2 * .pi / 3))
        case .thinking:
            return 1 + 0.05 * CGFloat(sin(time * 2 * .pi / 0.8))
        case .speaking:
            return 1 + 0.02 * CGFloat(sin(time * 2 * .pi / 1.4))
        case .listening:
            return 1.0
        case .error:
            return 0.8
        }
    }

    /// Two or three orange blinks when an error lands, then steady.
    private func errorFlicker(time: Double) -> CGFloat {
        guard case .error = state else { return 1 }
        return 0.55 + 0.45 * CGFloat(abs(sin(time * 2 * .pi * 1.5)))
    }

    private func drawGlow(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        intensity: CGFloat
    ) {
        // Layered translucent discs read as a soft bloom without a blur filter.
        for step in stride(from: 4, through: 1, by: -1) {
            let factor = 1 + CGFloat(step) * 0.42
            let rect = CGRect(
                x: center.x - radius * factor,
                y: center.y - radius * factor,
                width: radius * factor * 2,
                height: radius * factor * 2
            )
            let opacity = (0.085 / Double(step)) * Double(intensity)
            context.fill(Circle().path(in: rect), with: .color(edgeColor.opacity(opacity)))
        }
    }

    private func drawCore(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        level: CGFloat,
        intensity: CGFloat
    ) {
        let path: Path
        if case .listening = state {
            // The rim ripples in proportion to what the microphone hears.
            path = wobblePath(center: center, radius: radius, time: time, amplitude: 2 + level * 6)
        } else {
            path = Circle().path(
                in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }

        context.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [
                    coreColor.opacity(0.95 * Double(intensity)),
                    coreColor.opacity(0.45 * Double(intensity)),
                    edgeColor.opacity(0.05),
                ]),
                center: center,
                startRadius: 0,
                endRadius: radius * 1.05
            )
        )

        // Off-centre highlight, so the orb reads as a sphere rather than a disc.
        let highlightRadius = radius * 0.5
        let highlightCenter = CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.28)
        context.fill(
            Circle().path(
                in: CGRect(
                    x: highlightCenter.x - highlightRadius,
                    y: highlightCenter.y - highlightRadius,
                    width: highlightRadius * 2,
                    height: highlightRadius * 2
                )
            ),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.32 * Double(intensity)), .clear]),
                center: highlightCenter,
                startRadius: 0,
                endRadius: highlightRadius
            )
        )
    }

    /// A circle whose radius varies sinusoidally with angle.
    private func wobblePath(
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        amplitude: CGFloat
    ) -> Path {
        var path = Path()
        let steps = 90
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wobble = amplitude * CGFloat(sin(angle * 5 + time * 6))
                + amplitude * 0.5 * CGFloat(sin(angle * 8 - time * 4))
            let r = radius + wobble
            let point = CGPoint(
                x: center.x + r * CGFloat(cos(angle)),
                y: center.y + r * CGFloat(sin(angle))
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func drawRing(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        intensity: CGFloat
    ) {
        let ringRadius = radius * 1.32
        let rect = CGRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        )
        context.stroke(
            Circle().path(in: rect),
            with: .color(edgeColor.opacity(0.55 * Double(intensity))),
            lineWidth: 1
        )

        // A brighter arc sweeping the ring gives the orb a sense of rotation.
        if case .thinking = state {
            var arc = Path()
            let sweep = time.truncatingRemainder(dividingBy: 2) / 2 * 2 * .pi
            arc.addArc(
                center: center,
                radius: ringRadius,
                startAngle: .radians(sweep),
                endAngle: .radians(sweep + .pi / 3),
                clockwise: false
            )
            context.stroke(arc, with: .color(HermesColors.secondary), lineWidth: 2)
        }
    }

    /// Concentric waves expanding outward while the assistant speaks.
    private func drawRipples(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        level: CGFloat
    ) {
        let count = 3
        // Louder output pushes the waves out faster.
        let period = 2.2 - Double(level) * 0.9
        for index in 0..<count {
            let phase = (time / period + Double(index) / Double(count))
                .truncatingRemainder(dividingBy: 1)
            let rippleRadius = radius * (1.3 + CGFloat(phase) * 1.1)
            let opacity = (1 - phase) * 0.35
            let rect = CGRect(
                x: center.x - rippleRadius,
                y: center.y - rippleRadius,
                width: rippleRadius * 2,
                height: rippleRadius * 2
            )
            context.stroke(
                Circle().path(in: rect),
                with: .color(HermesColors.secondary.opacity(opacity)),
                lineWidth: 1.5
            )
        }
    }

    /// Points orbiting the core while the model is thinking.
    private func drawParticles(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double
    ) {
        let count = 5
        let orbit = radius * 1.55
        for index in 0..<count {
            let offset = Double(index) / Double(count) * 2 * .pi
            let angle = time * 1.6 + offset
            // A slight vertical squash reads as a tilted orbital plane.
            let point = CGPoint(
                x: center.x + orbit * CGFloat(cos(angle)),
                y: center.y + orbit * 0.42 * CGFloat(sin(angle))
            )
            // Dots on the far side of the orbit are dimmer and smaller.
            let depth = (sin(angle) + 1) / 2
            let dotRadius = 1.6 + CGFloat(depth) * 1.8
            context.fill(
                Circle().path(
                    in: CGRect(
                        x: point.x - dotRadius,
                        y: point.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                ),
                with: .color(HermesColors.secondary.opacity(0.35 + depth * 0.6))
            )
        }
    }
}

#Preview("Orb states") {
    HStack(spacing: 0) {
        ForEach(
            [OrbState.idle, .listening, .thinking, .speaking, .error("x")],
            id: \.label
        ) { state in
            VStack {
                OrbView(state: state, audioLevel: state == .listening ? 0.6 : 0.2,
                        frozenTime: 1.15)
                Text(state.label)
                    .font(HermesFonts.mono(9))
                    .tracking(1.5)
                    .foregroundStyle(HermesColors.text.opacity(0.5))
            }
        }
    }
    .padding(20)
    .background(HermesColors.background)
}

#Preview("Animated") {
    OrbView(state: .thinking)
        .padding(40)
        .background(HermesColors.background)
}
