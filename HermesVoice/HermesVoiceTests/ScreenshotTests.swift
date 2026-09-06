//  Renders the README screenshots from the real SwiftUI views. Opt-in, skipped in CI.

import SwiftUI
import XCTest

@testable import HermesVoice

/// Renders the README screenshots from the live view hierarchy.
///
/// These run on every `xcodebuild test`, including CI. That is deliberate: it keeps
/// the view hierarchy exercised, so a crash-on-render regression fails the build
/// instead of shipping.
///
/// The app is sandboxed, so the test host cannot write into the repo. It writes into
/// its container's temp directory and prints each path; `tools/screenshots.sh` copies
/// them into `docs/screenshots/`.
///
/// Rendering via `ImageRenderer` instead of capturing a window means no Screen
/// Recording permission, and identical output on every machine — the orb is drawn at
/// a frozen timestamp and the spectra are synthetic, so the renders are deterministic.
///
/// The limit of the approach: `ImageRenderer` cannot draw AppKit-backed controls, so
/// a `TextField` or `Picker` comes out as a placeholder swatch. The HUD is Canvas,
/// Text and custom buttons, so it renders faithfully; the settings sheet is not
/// rendered here, because the result would misrepresent it.
@MainActor
final class ScreenshotTests: XCTestCase {

    private var outputDirectory: URL!

    // setUpWithError is nonisolated, so the directory is prepared per test instead.
    @MainActor
    private func prepareOutputDirectory() throws {
        guard outputDirectory == nil else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermesvoice-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        outputDirectory = url
    }

    // MARK: - Fixtures

    private static let windowSize = CGSize(width: 520, height: 760)

    /// A plausible spectrum, so the waveform in the stills looks like speech.
    private static func spectrum(seed: Double, gain: Float = 1) -> [Float] {
        (0..<audioBandCount).map { index in
            let t = Double(index) / Double(audioBandCount)
            // Speech energy is concentrated low, with formant bumps above it.
            let envelope = exp(-t * 2.1)
            let formants = 0.45 * abs(sin(t * 9 + seed)) + 0.25 * abs(sin(t * 21 - seed * 2))
            return Float(min(1, (envelope + formants * envelope * 1.8) * 1.25)) * gain
        }
    }

    private static let conversation: [Message] = [
        Message(role: .user, content: "What can you do?"),
        Message(
            role: .assistant,
            content: "I listen on-device, send your words to Hermes, and read the reply "
                + "back out loud. Nothing but the text ever leaves your Mac."
        ),
        Message(role: .user, content: "How do I change the language?"),
        Message(
            role: .assistant,
            content: "Open settings and pick one. I switch instantly and keep this "
                + "conversation."
        ),
    ]

    // MARK: - Screenshots

    func testRenderIdle() throws {
        let state = AppState.preview(
            orbState: .idle,
            response: "Ready when you are. Hold the microphone button and speak.",
            messages: Self.conversation
        )
        try render(
            JarvisHUD(showingSettings: .constant(false)).environment(state),
            named: "01-idle"
        )
    }

    func testRenderListening() throws {
        let state = AppState.preview(
            orbState: .listening,
            transcript: "What is the weather like in Guayaquil today?"
        )
        state.audioEngine.setMetersForPreview(
            inputLevel: 0.72,
            outputLevel: 0,
            bands: Self.spectrum(seed: 1.2)
        )
        try render(
            JarvisHUD(showingSettings: .constant(false)).environment(state),
            named: "02-listening"
        )
    }

    func testRenderThinking() throws {
        let state = AppState.preview(
            orbState: .thinking,
            transcript: "What is the weather like in Guayaquil today?"
        )
        try render(
            JarvisHUD(showingSettings: .constant(false)).environment(state),
            named: "03-thinking"
        )
    }

    func testRenderSpeaking() throws {
        let state = AppState.preview(
            orbState: .speaking,
            transcript: "What is the weather like in Guayaquil today?",
            response: "It is warm and humid, around 29 degrees, with showers likely "
                + "later this afternoon."
        )
        state.audioEngine.setMetersForPreview(
            inputLevel: 0,
            outputLevel: 0.66,
            bands: Self.spectrum(seed: 3.7, gain: 0.92)
        )
        try render(
            JarvisHUD(showingSettings: .constant(false)).environment(state),
            named: "04-speaking"
        )
    }

    func testRenderHistory() throws {
        let state = AppState.preview(
            orbState: .idle,
            messages: Self.conversation
        )
        try render(
            ConversationHistoryView(isPresented: .constant(true)).environment(state),
            named: "05-history"
        )
    }

    func testRenderOrbStates() throws {
        // A strip of all five states, frozen at a timestamp that shows each one well.
        let strip = HStack(spacing: 0) {
            ForEach(
                [OrbState.idle, .listening, .thinking, .speaking, .error("x")],
                id: \.label
            ) { state in
                VStack(spacing: 10) {
                    // OrbView draws a fixed 360pt canvas so its glow is never clipped;
                    // scale rather than frame it, or the canvases overlap.
                    OrbView(
                        state: state,
                        audioLevel: state == .listening ? 0.65 : 0.3,
                        frozenTime: 1.15
                    )
                    .scaleEffect(0.52)
                    .frame(width: 192, height: 192)
                    Text(state.label)
                        .font(HermesFonts.mono(9, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(HermesColors.text.opacity(0.45))
                }
            }
        }
        .padding(.vertical, 22)
        .background(HermesColors.background)

        try render(strip, named: "06-orb-states", size: nil)
    }

    // MARK: - Rendering

    private func render(
        _ view: some View,
        named name: String,
        size: CGSize? = ScreenshotTests.windowSize
    ) throws {
        try prepareOutputDirectory()
        let directory = outputDirectory!

        var wrapped = AnyView(
            view
                .environment(\.colorScheme, .dark)
                .environment(\.isStaticSnapshot, true)
                .background(HermesColors.background)
        )
        if let size {
            wrapped = AnyView(wrapped.frame(width: size.width, height: size.height))
        }

        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2
        renderer.isOpaque = true

        let image = try XCTUnwrap(renderer.nsImage, "ImageRenderer returned no image")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("wrote \(url.path) (\(bitmap.pixelsWide)×\(bitmap.pixelsHigh))")
    }
}
