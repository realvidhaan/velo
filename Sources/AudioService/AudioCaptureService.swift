import Foundation
import AVFoundation
import os

/// Errors surfaced by `AudioCaptureService` so callers can fail gracefully
/// instead of the app crashing.
public enum AudioCaptureError: Error {
    /// The microphone input format was invalid (0 Hz / 0 channels) even after a
    /// reset — installing a tap with it would raise an uncatchable Obj-C exception.
    case invalidInputFormat
}

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

    /// When true, capture runs through Apple's `AUVoiceProcessingIO` unit — AGC
    /// (boosts quiet/whispered speech), ambient-noise suppression, and echo
    /// cancellation — instead of the raw input node. Toggleable because VP-IO is
    /// VoIP-tuned and can occasionally pump gain or over-suppress a genuine
    /// whisper; with it off, `GainNormalizer` downstream still handles the whisper
    /// boost. Changing it while running takes effect on the next `start()`.
    public var voiceProcessing = true

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
        configureVoiceProcessing()
        // Prepare *before* reading the input format. A stopped/idle engine's input
        // node can report an invalid format (0 Hz / 0 channels); preparing pulls it
        // back to the live hardware format. installTap then validates it.
        engine.prepare()
        try installTap()
        try engine.start()
        running = true
        log.info("Audio engine started")
    }

    /// Toggles Apple voice processing on the input node. Must run **before**
    /// `engine.start()` and before the tap is installed: enabling it rebuilds the
    /// IO unit and changes the input format (which the tap re-reads afterwards).
    /// Enabling VP on the input node instantiates the shared VP-IO unit that
    /// couples input and output, so we reference `outputNode` to force it to
    /// materialize. The whole thing is best-effort — `setVoiceProcessingEnabled`
    /// can `throw`, and a failure must degrade to raw capture, never break
    /// dictation (`GainNormalizer` downstream still boosts whispers).
    private func configureVoiceProcessing() {
        let input = engine.inputNode
        do {
            if input.isVoiceProcessingEnabled != voiceProcessing {
                _ = engine.outputNode // materialize the coupled VP-IO output side
                try input.setVoiceProcessingEnabled(voiceProcessing)
            }
            if voiceProcessing {
                // AGC is the whisper-boost half of VP-IO; keep it explicitly on.
                input.isVoiceProcessingAGCEnabled = true
            }
            log.info("Voice processing \(self.voiceProcessing ? "enabled" : "disabled")")
        } catch {
            log.error("Voice processing setup failed; using raw capture: \(error.localizedDescription, privacy: .public)")
        }
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

    private func installTap() throws {
        let input = engine.inputNode
        // Never install two taps on the same bus. If a previous session errored
        // out after installing but before `stop()` removed it (or a config-change
        // re-tap raced), a leftover tap makes `installTapOnBus` raise
        // "already installed". `removeTap` is a safe no-op when none is present.
        input.removeTap(onBus: 0)

        var format = input.outputFormat(forBus: 0)
        if format.channelCount == 0 || format.sampleRate == 0 {
            // The input node went stale while idle (the classic "quits on the 2nd
            // Fn press" trigger). Reset + re-prepare to repull the live format.
            engine.reset()
            engine.prepare()
            format = input.outputFormat(forBus: 0)
        }
        // Crucial: installing a tap with an invalid format raises an Obj-C
        // NSException, which a Swift `do/catch` CANNOT catch — it calls abort() and
        // kills the whole app. So validate first and surface a Swift error instead;
        // `start()`'s caller then fails gracefully and the app stays alive.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            log.error("Input format still invalid (\(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch); skipping tap")
            throw AudioCaptureError.invalidInputFormat
        }

        // The block MUST be `@Sendable` (non-isolated). AVAudioEngine invokes it
        // on its realtime audio thread; a plain trailing closure formed here would
        // inherit this method's @MainActor isolation, and the Swift 6 runtime then
        // traps (SIGTRAP) when it runs off-main. Everything touched synchronously
        // here is nonisolated; actor-isolated work hops via `Task { @MainActor }`.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable [weak self] buffer, _ in
            let rms = Self.rms(of: buffer)
            // The engine may recycle `buffer` once this block returns, so copy it
            // before handing it to an async task on the main actor.
            guard let copy = Self.copy(buffer) else { return }
            // `copy` is a freshly-allocated, uniquely-owned buffer used nowhere
            // else, so handing it to the main actor is race-free. The region
            // checker can't prove that (it was built by reading `buffer`), so opt
            // this hand-off out of the check explicitly.
            nonisolated(unsafe) let handoff = copy
            Task { @MainActor [weak self] in
                self?.publish(rms: rms, buffer: handoff)
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

    /// `nonisolated` is load-bearing: AVFAudio posts
    /// `.AVAudioEngineConfigurationChange` on a **background** dispatch queue
    /// (notably when the audio IO unit is torn down and re-established on
    /// **sleep/wake**). A `@MainActor`-isolated `@objc` selector invoked off-main
    /// trips Swift 6's executor assertion and SIGTRAPs the whole app — which is
    /// exactly why Velo was dying every time the Mac woke. So take the
    /// notification on whatever thread it arrives on and hop to the main actor to
    /// do the real work.
    /// Internal (not private) so a test can invoke it off-main to reproduce the
    /// sleep/wake crash condition without real audio hardware.
    @objc nonisolated func configurationChanged(_ note: Notification) {
        Task { @MainActor [weak self] in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        // Input device changed (e.g. AirPods connected) or the audio unit was
        // rebuilt on wake. Re-tap if we were running.
        guard running else { return }
        log.info("Audio configuration changed; re-tapping input")
        // A device switch or wake-time IO-unit rebuild can drop voice processing,
        // so re-assert it before re-tapping. `setVoiceProcessingEnabled` only
        // succeeds on a **stopped** engine, though — reconfiguring it while the
        // engine is still running throws (silently, here) and leaves capture in
        // the wrong voice-processing state. So stop first, reconfigure, then
        // re-tap and restart.
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        configureVoiceProcessing()
        engine.prepare()
        do {
            try installTap()
            try engine.start()
        } catch {
            // Don't crash on a bad re-tap: mark ourselves stopped so the next Fn
            // press does a clean cold start instead of assuming we're still live.
            log.error("Failed to re-tap after config change: \(error.localizedDescription, privacy: .public)")
            running = false
            setLevel(0)
        }
    }

    // MARK: Helpers

    /// Deep-copies a PCM buffer so it survives past the realtime tap block.
    /// `nonisolated`: called from AVAudioEngine's realtime thread, not the main
    /// actor. It only touches the passed-in buffer, so it needs no isolation —
    /// and requiring main-actor isolation here traps (SIGTRAP) at runtime when
    /// the tap fires off-main.
    ///
    private nonisolated static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in 0..<min(src.count, dst.count) {
            guard let s = src[i].mData, let d = dst[i].mData else { continue }
            let bytes = Int(src[i].mDataByteSize)
            memcpy(d, s, bytes)
            dst[i].mDataByteSize = src[i].mDataByteSize
        }
        return copy
    }

    /// `nonisolated` for the same reason as `copy`: it runs on the realtime tap
    /// thread and only reads the passed-in buffer.
    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
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
