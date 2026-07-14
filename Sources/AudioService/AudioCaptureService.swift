import Foundation
import AVFoundation
import os

/// Captures microphone audio with `AVAudioEngine`. In M1 it exposes a smoothed
/// input **level** (0…1) for the recording indicator. Later milestones add the
/// PCM tap feed into `SpeechAnalyzer` and a WAV sidecar; the tap is already
/// installed here so those hook in without restructuring.
@MainActor
public final class AudioCaptureService {
    private let log = Logger(subsystem: "com.flowclone.app", category: "Audio")

    private let engine = AVAudioEngine()
    private var running = false

    /// Smoothed 0…1 microphone level, updated on the main actor while recording.
    public private(set) var level: Float = 0
    /// Called on the main actor whenever `level` changes.
    public var onLevel: ((Float) -> Void)?

    /// Optional raw-buffer sink (used by the transcription engine in M2+).
    public var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    // MARK: Permission

    public static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: Lifecycle

    public func start() throws {
        guard !running else { return }
        installTap()
        engine.prepare()
        try engine.start()
        running = true
        log.info("Audio engine started")
    }

    public func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        setLevel(0)
        log.info("Audio engine stopped")
    }

    // MARK: Tap

    private func installTap() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let rms = Self.rms(of: buffer)
            Task { @MainActor [weak self] in
                self?.publish(rms: rms, buffer: buffer)
            }
        }
    }

    private func publish(rms: Float, buffer: AVAudioPCMBuffer) {
        // Convert RMS to a perceptual 0…1 level (dBFS mapped from -50…0).
        let db = 20 * log10(max(rms, 1e-7))
        let normalized = max(0, min(1, (db + 50) / 50))
        // Exponential smoothing so the indicator isn't jittery.
        let smoothed = level * 0.6 + normalized * 0.4
        setLevel(smoothed)
        onBuffer?(buffer)
    }

    private func setLevel(_ value: Float) {
        level = value
        onLevel?(value)
    }

    @objc private func configurationChanged(_ note: Notification) {
        // Input device changed (e.g. AirPods connected). Re-tap if we were running.
        guard running else { return }
        log.info("Audio configuration changed; re-tapping input")
        engine.inputNode.removeTap(onBus: 0)
        installTap()
        if !engine.isRunning {
            do { try engine.start() } catch {
                log.error("Failed to restart engine after config change: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Helpers

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frames {
            let s = samples[i]
            sum += s * s
        }
        return (sum / Float(frames)).squareRoot()
    }
}
