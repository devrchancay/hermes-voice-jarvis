//  Shared AVAudioEngine: microphone capture, TTS playback, and level/spectrum metering.

import Accelerate
import AVFoundation
import Foundation
import os

/// Number of bars the waveform view draws.
let audioBandCount = 28

// MARK: - Metering storage

/// Lock-protected hand-off between the realtime audio thread and the main actor.
///
/// The tap callback runs on a realtime thread where allocation and actor hops are
/// forbidden, so it writes here and a 30 Hz timer on the main actor reads it back.
private final class MeterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _level: Float = 0
    private var _bands = [Float](repeating: 0, count: audioBandCount)

    func write(level: Float, bands: [Float]) {
        lock.lock()
        _level = level
        _bands = bands
        lock.unlock()
    }

    func read() -> (level: Float, bands: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        return (_level, _bands)
    }

    func reset() {
        write(level: 0, bands: [Float](repeating: 0, count: audioBandCount))
    }
}

/// Holds the buffer handler across the actor boundary so the tap can call it directly.
private final class BufferHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func set(_ new: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?) {
        lock.lock()
        handler = new
        lock.unlock()
    }

    func call(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        lock.lock()
        let current = handler
        lock.unlock()
        current?(buffer, time)
    }
}

// MARK: - Spectrum analysis

/// Turns a PCM buffer into a small set of normalised magnitude bands.
private final class SpectrumAnalyzer: @unchecked Sendable {
    private let log2n: vDSP_Length = 10
    private let count = 1 << 10          // 1024 samples per FFT
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let lock = NSLock()
    private var scratch: [Float]
    private var smoothed = [Float](repeating: 0, count: audioBandCount)

    init?() {
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            return nil
        }
        self.fft = fft
        self.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                  count: count, isHalfWindow: false)
        self.scratch = [Float](repeating: 0, count: count)
    }

    /// Returns `audioBandCount` log-spaced bands in 0...1, plus the frame's RMS.
    func analyze(_ buffer: AVAudioPCMBuffer) -> (level: Float, bands: [Float])? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        // RMS over the whole frame, mapped from dBFS to a perceptual 0...1.
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frames))
        let db = 20 * log10(max(rms, 1e-7))
        let level = max(0, min(1, (db + 55) / 55))

        // Take the most recent `count` samples, zero-padding a short buffer.
        let take = min(frames, count)
        let offset = frames - take
        scratch.withUnsafeMutableBufferPointer { dst in
            dst.baseAddress!.update(repeating: 0, count: count)
            dst.baseAddress!.update(from: channel + offset, count: take)
        }
        vDSP.multiply(scratch, window, result: &scratch)

        var real = [Float](repeating: 0, count: count / 2)
        var imag = [Float](repeating: 0, count: count / 2)
        var magnitudes = [Float](repeating: 0, count: count / 2)

        scratch.withUnsafeBufferPointer { input in
            input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: count / 2) { typed in
                real.withUnsafeMutableBufferPointer { realPtr in
                    imag.withUnsafeMutableBufferPointer { imagPtr in
                        var split = DSPSplitComplex(realp: realPtr.baseAddress!,
                                                    imagp: imagPtr.baseAddress!)
                        vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(count / 2))
                        fft.forward(input: split, output: &split)
                        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(count / 2))
                    }
                }
            }
        }

        // Group the spectrum into log-spaced bands — low bins carry most speech energy.
        let bins = count / 2
        var bands = [Float](repeating: 0, count: audioBandCount)
        let minBin = 2.0
        let maxBin = Double(bins - 1)
        for band in 0..<audioBandCount {
            let t0 = Double(band) / Double(audioBandCount)
            let t1 = Double(band + 1) / Double(audioBandCount)
            let lo = Int(minBin * pow(maxBin / minBin, t0))
            let hi = max(lo + 1, Int(minBin * pow(maxBin / minBin, t1)))
            var sum: Float = 0
            for bin in lo..<min(hi, bins) { sum += magnitudes[bin] }
            let mean = sum / Float(max(1, min(hi, bins) - lo))
            let bandDb = 20 * log10(max(mean / Float(count), 1e-7))
            bands[band] = max(0, min(1, (bandDb + 70) / 55))
        }

        // Asymmetric smoothing: rise fast, fall slow. Reads far better than raw values.
        for index in 0..<audioBandCount {
            let target = bands[index]
            let previous = smoothed[index]
            smoothed[index] = target > previous
                ? previous + (target - previous) * 0.6
                : previous + (target - previous) * 0.18
        }
        return (level, smoothed)
    }

    func reset() {
        lock.lock()
        smoothed = [Float](repeating: 0, count: audioBandCount)
        lock.unlock()
    }
}

// MARK: - Audio engine

/// Owns the process-wide `AVAudioEngine`.
///
/// A single engine serves both the microphone tap and TTS playback: running two
/// engines against the same hardware device is unreliable, and sharing one lets the
/// recogniser, the waveform, and interruption detection read the same buffers.
@MainActor
@Observable
final class AudioEngine {
    /// Smoothed microphone level, 0...1.
    private(set) var inputLevel: Float = 0
    /// Smoothed TTS output level, 0...1.
    private(set) var outputLevel: Float = 0
    /// Microphone spectrum bands, 0...1.
    private(set) var inputBands = [Float](repeating: 0, count: audioBandCount)
    /// TTS output spectrum bands, 0...1.
    private(set) var outputBands = [Float](repeating: 0, count: audioBandCount)

    private(set) var isInputRunning = false
    private(set) var isOutputRunning = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private let inputMeter = MeterBox()
    private let outputMeter = MeterBox()
    private let inputHandler = BufferHandlerBox()
    private let inputAnalyzer = SpectrumAnalyzer()
    private let outputAnalyzer = SpectrumAnalyzer()

    private var meterTimer: Timer?
    private var playerConnected = false

    private static let logger = Logger(subsystem: "com.desarol.hermes-voice", category: "AudioEngine")

    // MARK: Microphone

    /// Native format of the input hardware. Touching this initialises the mic.
    var inputFormat: AVAudioFormat {
        engine.inputNode.inputFormat(forBus: 0)
    }

    /// Installs a handler that receives every microphone buffer on the audio thread.
    ///
    /// The handler must be realtime-safe: no allocation, no locks held for long.
    func setInputBufferHandler(_ handler: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?) {
        inputHandler.set(handler)
    }

    func startInput() throws {
        guard !isInputRunning else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioEngineError.noInputDevice
        }

        let meter = inputMeter
        let analyzer = inputAnalyzer
        let handler = inputHandler

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            handler.call(buffer, time)
            if let result = analyzer?.analyze(buffer) {
                meter.write(level: result.level, bands: result.bands)
            }
        }

        try startEngineIfNeeded()
        isInputRunning = true
        startMeterTimer()
        Self.logger.info("Microphone tap started at \(format.sampleRate, privacy: .public) Hz")
    }

    func stopInput() {
        guard isInputRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        inputHandler.set(nil)
        inputMeter.reset()
        inputAnalyzer?.reset()
        inputLevel = 0
        inputBands = [Float](repeating: 0, count: audioBandCount)
        isInputRunning = false
        stopEngineIfIdle()
        Self.logger.info("Microphone tap stopped")
    }

    // MARK: TTS playback

    /// Prepares the player node so synthesised buffers can be scheduled.
    func startOutput(format: AVAudioFormat) throws {
        if !playerConnected {
            engine.attach(player)
            playerConnected = true
        }
        // Reconnect whenever the format changes (voices differ in sample rate).
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let meter = outputMeter
        let analyzer = outputAnalyzer
        player.removeTap(onBus: 0)
        player.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            if let result = analyzer?.analyze(buffer) {
                meter.write(level: result.level, bands: result.bands)
            }
        }

        try startEngineIfNeeded()
        player.play()
        isOutputRunning = true
        startMeterTimer()
    }

    /// Queues one synthesised buffer for playback.
    func schedule(_ buffer: AVAudioPCMBuffer) async {
        guard isOutputRunning else { return }
        await withCheckedContinuation { continuation in
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                continuation.resume()
            }
        }
    }

    /// Queues a buffer without waiting for it to finish.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard isOutputRunning else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stopOutput() {
        guard isOutputRunning else { return }
        player.stop()
        player.removeTap(onBus: 0)
        outputMeter.reset()
        outputAnalyzer?.reset()
        outputLevel = 0
        outputBands = [Float](repeating: 0, count: audioBandCount)
        isOutputRunning = false
        stopEngineIfIdle()
    }

    /// Drops everything queued but keeps the node ready for the next utterance.
    func flushOutput() {
        guard isOutputRunning else { return }
        player.stop()
        outputMeter.reset()
        outputAnalyzer?.reset()
        outputLevel = 0
        outputBands = [Float](repeating: 0, count: audioBandCount)
        player.play()
    }

    // MARK: Engine lifecycle

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Self.logger.error("Engine failed to start: \(error.localizedDescription, privacy: .public)")
            throw AudioEngineError.engineFailed(error.localizedDescription)
        }
    }

    private func stopEngineIfIdle() {
        guard !isInputRunning, !isOutputRunning else { return }
        if engine.isRunning { engine.stop() }
        stopMeterTimer()
    }

    // MARK: Metering

    private func startMeterTimer() {
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publishMeters() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func publishMeters() {
        if isInputRunning {
            let reading = inputMeter.read()
            inputLevel = reading.level
            inputBands = reading.bands
        }
        if isOutputRunning {
            let reading = outputMeter.read()
            outputLevel = reading.level
            outputBands = reading.bands
        }
    }

    // MARK: Permission

    /// Requests microphone access. Returns immediately if already decided.
    static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}

enum AudioEngineError: LocalizedError {
    case noInputDevice
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available."
        case .engineFailed(let detail):
            return "The audio engine could not start: \(detail)"
        }
    }
}

// MARK: - Preview support

#if DEBUG
extension AudioEngine {
    /// Injects fake meter readings so previews and screenshots can show a waveform
    /// without opening the microphone.
    func setMetersForPreview(inputLevel: Float, outputLevel: Float, bands: [Float]) {
        self.inputLevel = inputLevel
        self.outputLevel = outputLevel
        self.inputBands = bands
        self.outputBands = bands
    }
}
#endif
