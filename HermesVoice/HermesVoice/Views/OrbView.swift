//  The central orb: a particle torus of light filaments orbiting a hollow core.

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

    /// Room for the widest ripple and the outer bloom.
    private var canvasSide: CGFloat { 360 }

    /// Tilt of the torus away from the viewer. Small, so the ring stays near face-on.
    private let tilt: Double = 0.42

    /// Distance to the projection plane. Large enough for a hint of perspective only.
    private let focalLength: CGFloat = 900

    /// Points sampled along each filament.
    private let pointsPerStrand = 220

    /// Depth slices the particles are batched into, so a frame costs a handful of fills.
    private let depthSlices = 8

    // MARK: - Look

    /// Everything the current state changes about the torus.
    private struct Look {
        /// Radius of the ring the filaments are wound around.
        var majorRadius: CGFloat
        /// Radius of the tube the filaments wind through.
        var tubeRadius: CGFloat
        /// How far the ring is pushed out of round by the travelling waves.
        var turbulence: CGFloat
        /// In-plane rotation, radians per second.
        var spin: Double
        /// Windings of a filament around the tube per lap of the ring.
        var twist: Double
        /// Speed the windings travel along the tube.
        var flow: Double
        /// Number of filaments.
        var strands: Int
        /// Overall opacity multiplier.
        var brightness: Double
        /// Colour at the far side of the ring.
        var farHex: UInt32
        /// Colour at the near side of the ring.
        var nearHex: UInt32
    }

    private func look(level: CGFloat) -> Look {
        switch state {
        case .idle:
            return Look(
                majorRadius: 86, tubeRadius: 12, turbulence: 0.055,
                spin: 0.10, twist: 5, flow: 0.30,
                strands: 6, brightness: 0.72,
                farHex: HermesColors.primaryHex, nearHex: HermesColors.secondaryHex
            )
        case .listening:
            return Look(
                majorRadius: 88 + level * 6, tubeRadius: 13 + level * 9,
                turbulence: 0.05 + level * 0.09,
                spin: 0.18, twist: 5, flow: 0.9 + Double(level) * 1.2,
                strands: 7, brightness: 0.92 + Double(level) * 0.08,
                farHex: HermesColors.primaryHex, nearHex: HermesColors.secondaryHex
            )
        case .thinking:
            return Look(
                majorRadius: 84, tubeRadius: 16, turbulence: 0.11,
                spin: 0.5, twist: 7, flow: 1.7,
                strands: 8, brightness: 1,
                farHex: HermesColors.primaryHex, nearHex: HermesColors.secondaryHex
            )
        case .speaking:
            return Look(
                majorRadius: 87 + level * 4, tubeRadius: 14 + level * 7,
                turbulence: 0.07 + level * 0.05,
                spin: 0.22, twist: 6, flow: 1.1,
                strands: 7, brightness: 0.95,
                farHex: HermesColors.secondaryHex, nearHex: HermesColors.secondaryHex
            )
        case .error:
            return Look(
                majorRadius: 68, tubeRadius: 9, turbulence: 0.03,
                spin: 0.06, twist: 4, flow: 0.2,
                strands: 5, brightness: 0.85,
                farHex: HermesColors.errorHex, nearHex: HermesColors.errorHex
            )
        }
    }

    // MARK: - Drawing

    private func draw(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let level = CGFloat(max(0, min(1, audioLevel)))
        let intensity = errorFlicker(time: time)

        var look = look(level: level)
        look.majorRadius *= pulseScale(time: time)

        drawCoreHalo(context, center: center, look: look, level: level, intensity: intensity)
        drawBloom(context, center: center, look: look, intensity: intensity)

        if case .speaking = state {
            drawRipples(context, center: center, look: look, time: time, level: level)
        }

        drawTorus(context, center: center, look: look, time: time, intensity: intensity)

        if case .thinking = state {
            drawSweep(context, center: center, look: look, time: time)
        }
    }

    /// Slow breath at rest, faster pulse while thinking.
    private func pulseScale(time: Double) -> CGFloat {
        switch state {
        case .idle:
            return 1 + 0.025 * CGFloat(sin(time * 2 * .pi / 4))
        case .thinking:
            return 1 + 0.04 * CGFloat(sin(time * 2 * .pi / 1.1))
        case .speaking:
            return 1 + 0.02 * CGFloat(sin(time * 2 * .pi / 1.4))
        case .listening:
            return 1
        case .error:
            return 1
        }
    }

    /// Orange blinks while an error is showing.
    private func errorFlicker(time: Double) -> CGFloat {
        guard case .error = state else { return 1 }
        return 0.55 + 0.45 * CGFloat(abs(sin(time * 2 * .pi * 1.5)))
    }

    /// The filaments themselves: a torus of points, batched by depth.
    private func drawTorus(
        _ context: GraphicsContext,
        center: CGPoint,
        look: Look,
        time: Double,
        intensity: CGFloat
    ) {
        let cosTilt = CGFloat(cos(tilt))
        let sinTilt = CGFloat(sin(tilt))
        // Depth spans the tilted ring plus the tube around it.
        let depthRange = max(look.majorRadius * sinTilt + look.tubeRadius, 1)

        var slices = [Path](repeating: Path(), count: depthSlices)

        for strand in 0..<look.strands {
            let index = Double(strand)
            // The golden angle keeps the filaments evenly out of step with each other.
            let strandPhase = index * 2.399963
            let strandRadius = look.majorRadius * (1 + 0.06 * CGFloat(sin(index * 1.7)))

            for step in 0..<pointsPerStrand {
                let progress = Double(step) / Double(pointsPerStrand) * 2 * .pi
                // Uneven sampling clumps the points, so the filament reads as dust
                // rather than as a dotted line.
                let theta = progress + 0.16 * sin(progress * 3 + strandPhase)
                    + time * look.spin

                let wave = sin(3 * theta + time * 0.6 + strandPhase)
                    + 0.7 * sin(5 * theta - time * 0.45 + index)
                    + 0.45 * sin(7 * theta + time * 0.9 + strandPhase)
                    + 0.25 * sin(11 * theta - time * 0.7)
                let major = strandRadius * (1 + look.turbulence * CGFloat(wave))

                // Thickness of the tube breathes around the ring, so the filaments
                // gather into knots and fan out again.
                let tube = look.tubeRadius
                    * (0.55 + 0.45 * CGFloat(sin(2 * theta + time * 0.5 + index)))
                let phi = theta * look.twist + time * look.flow + strandPhase

                let radial = major + tube * CGFloat(cos(phi))
                let flatX = radial * CGFloat(cos(theta))
                let flatY = radial * CGFloat(sin(theta))
                let flatZ = tube * CGFloat(sin(phi))

                // Tilt about the horizontal axis, then project.
                let y = flatY * cosTilt - flatZ * sinTilt
                let z = flatY * sinTilt + flatZ * cosTilt
                let scale = focalLength / (focalLength - z)

                let depth = max(0, min(1, Double(z / depthRange + 1) / 2))
                let slice = min(depthSlices - 1, Int(depth * Double(depthSlices)))
                let dotRadius = (0.5 + CGFloat(depth) * 0.85) * scale

                let point = CGPoint(x: center.x + flatX * scale, y: center.y + y * scale)
                slices[slice].addEllipse(
                    in: CGRect(
                        x: point.x - dotRadius,
                        y: point.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                )
            }
        }

        for (slice, path) in slices.enumerated() {
            let t = Double(slice) / Double(depthSlices - 1)
            // Near points are brighter and cyan, far points dim and blue.
            let opacity = (0.30 + 0.70 * pow(t, 1.3)) * look.brightness * Double(intensity)
            context.fill(
                path,
                with: .color(HermesColors.blend(look.farHex, look.nearHex, t, opacity: opacity))
            )
        }
    }

    /// Wide, faint strokes along the ring, standing in for a bloom filter.
    private func drawBloom(
        _ context: GraphicsContext,
        center: CGPoint,
        look: Look,
        intensity: CGFloat
    ) {
        for step in 1...3 {
            let width = look.tubeRadius * CGFloat(step) * 1.6
            let rect = CGRect(
                x: center.x - look.majorRadius,
                y: center.y - look.majorRadius,
                width: look.majorRadius * 2,
                height: look.majorRadius * 2
            )
            let opacity = (0.032 / Double(step)) * look.brightness * Double(intensity)
            context.stroke(
                Circle().path(in: rect),
                with: .color(Color(hex: look.nearHex, opacity: opacity)),
                lineWidth: width
            )
        }
    }

    /// The hollow middle: a dim disc and two hairlines that answer to the audio level.
    private func drawCoreHalo(
        _ context: GraphicsContext,
        center: CGPoint,
        look: Look,
        level: CGFloat,
        intensity: CGFloat
    ) {
        let coreRadius = look.majorRadius * 0.46
        context.fill(
            Circle().path(
                in: CGRect(
                    x: center.x - coreRadius,
                    y: center.y - coreRadius,
                    width: coreRadius * 2,
                    height: coreRadius * 2
                )
            ),
            with: .radialGradient(
                Gradient(colors: [
                    Color(
                        hex: look.nearHex,
                        opacity: (0.06 + Double(level) * 0.10) * Double(intensity)
                    ),
                    .clear,
                ]),
                center: center,
                startRadius: 0,
                endRadius: coreRadius
            )
        )

        for factor in [0.30, 0.42] as [CGFloat] {
            let radius = look.majorRadius * factor
            context.stroke(
                Circle().path(
                    in: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                ),
                with: .color(Color(hex: look.nearHex, opacity: 0.10 * Double(intensity))),
                lineWidth: 0.5
            )
        }
    }

    /// Concentric waves expanding outward while the assistant speaks.
    private func drawRipples(
        _ context: GraphicsContext,
        center: CGPoint,
        look: Look,
        time: Double,
        level: CGFloat
    ) {
        let count = 3
        // Louder output pushes the waves out faster.
        let period = 2.2 - Double(level) * 0.9
        for index in 0..<count {
            let phase = (time / period + Double(index) / Double(count))
                .truncatingRemainder(dividingBy: 1)
            let radius = look.majorRadius * (1.25 + CGFloat(phase) * 0.75)
            let opacity = (1 - phase) * 0.28
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(
                Circle().path(in: rect),
                with: .color(HermesColors.secondary.opacity(opacity)),
                lineWidth: 1.2
            )
        }
    }

    /// A bright arc sweeping an outer ring, so thinking reads as work in progress.
    private func drawSweep(
        _ context: GraphicsContext,
        center: CGPoint,
        look: Look,
        time: Double
    ) {
        let radius = look.majorRadius * 1.34
        var arc = Path()
        let sweep = time.truncatingRemainder(dividingBy: 2) / 2 * 2 * .pi
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(sweep),
            endAngle: .radians(sweep + .pi / 3),
            clockwise: false
        )
        context.stroke(
            arc,
            with: .linearGradient(
                Gradient(colors: [HermesColors.secondary.opacity(0), HermesColors.secondary]),
                startPoint: CGPoint(x: center.x - radius, y: center.y),
                endPoint: CGPoint(x: center.x + radius, y: center.y)
            ),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )
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
