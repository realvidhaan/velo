import Foundation
import AVFoundation
import ObjCSupport
import os

/// Errors surfaced by `AudioCaptureService` so callers can fail gracefully
/// instead of the app crashing.
public enum AudioCaptureError: Error, CustomStringConvertible {
    /// The microphone input format was invalid (0 Hz / 0 channels) even after a
    /// reset — installing a tap with it would raise an uncatchable Obj-C exception.
    case invalidInputFormat
    /// `installTap` raised an Obj-C `NSException` (carried reason). Caught by the
    /// ObjCSupport shim and rethrown as a Swift error so we degrade, not abort.
    case tapInstallFailed(String)
    /// `engine.start()` raised an Obj-C `NSException` (carried reason).
    case engineStartFailed(String)

    public var description: String {
        switch self {
        case .invalidInputFormat: return "microphone input format invalid (0 Hz / 0 channels)"
        case .tapInstallFailed(let reason): return "installTap raised: \(reason)"
        case .engineStartFailed(let reason): return "engine.start raised: \(reason)"
        }
    }
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

    /// How long to keep retrying a cold start before giving up. After the Mac has
    /// idled, macOS powers the input hardware down; the input node then reports a
    /// 0 Hz / 0 ch format for ~100–500 ms while the HAL and VoiceProcessingIO unit
    /// spin back up. A *synchronous* retry re-reads that same 0 Hz instantly and
    /// still fails — which is the "wait a while, press Fn, error, can't dictate"
    /// bug — so we retry with a short sleep between attempts until the hardware
    /// reports a real format or this budget is spent.
    private static let coldStartBudget: Duration = .milliseconds(1500)
    private static let coldStartRetryDelay: Duration = .milliseconds(120)

    /// Starts capture, tolerating a powered-down mic after idle. Each attempt
    /// (re)configures voice processing, prepares the engine, and installs the tap;
    /// on failure it tears the engine down, waits a beat for the hardware to wake,
    /// and retries until `coldStartBudget` is spent, then rethrows the last error.
    /// `async` because the settle wait is the whole point — the old synchronous
    /// retry never gave the hardware time to report a valid format.
    public func start() async throws {
        guard !running else { return }
        var lastAttempt = 0
        try await Self.retryingColdStart(
            budget: Self.coldStartBudget, delay: Self.coldStartRetryDelay
        ) { attempt in
            lastAttempt = attempt
            configureVoiceProcessing()
            // Prepare *before* reading the input format. A stopped/idle engine's
            // input node can report an invalid format (0 Hz / 0 ch); preparing
            // pulls it toward the live hardware format, which installTap validates.
            engine.prepare()
            do {
                try installTapAndStart()
            } catch {
                // Stale/racy state (idle-powered-down input, a config-change re-tap
                // mid-rebuild, or the IO unit still waking): tear down to a cold
                // slate so the loop settles and retries on a fresh engine.
                log.error("Audio start attempt \(attempt, privacy: .public) failed (\(String(describing: error), privacy: .public)); settling then retrying")
                hardResetEngine()
                throw error
            }
        }
        running = true
        log.info("Audio engine started (attempt \(lastAttempt, privacy: .public))")
    }

    /// Runs `attempt` (1-indexed) until it succeeds or `budget` elapses, sleeping
    /// `delay` between tries, then rethrows the last error. Extracted so the
    /// settle/retry timing is unit-testable without real audio hardware. The sleep
    /// propagates cancellation — a quick key release aborts an in-flight start.
    @MainActor
    static func retryingColdStart(
        budget: Duration,
        delay: Duration,
        attempt: (Int) async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: budget)
        var n = 0
        while true {
            n += 1
            do {
                try await attempt(n)
                return
            } catch {
                // Clamp the settle wait to the remaining budget so a failure near
                // the deadline can't overshoot it by a full `delay`, and don't
                // begin another attempt once the budget is spent.
                let remaining = deadline - ContinuousClock.now
                if remaining <= .zero { throw error }
                try await Task.sleep(for: min(delay, remaining))
            }
        }
    }

    /// Tears the engine down to a clean cold state so the next attempt starts from
    /// scratch rather than from whatever partial state made the last one raise.
    /// Voice-processing config + `prepare()` are re-done at the top of `start()`'s
    /// retry loop, so they are intentionally not repeated here — repeating them
    /// after the `reset()` was the ordering race that could tear down a
    /// just-built VoiceProcessingIO unit right before the format read.
    private func hardResetEngine() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        engine.reset()
    }

    /// Best-effort: spin the input graph up ahead of the next capture so the first
    /// Fn press after the Mac wakes isn't a cold start against powered-down input
    /// hardware. Called from an `NSWorkspace.didWakeNotification` hook. Does not
    /// start the engine (which would light the mic-in-use indicator) — `prepare()`
    /// is enough to pull the input node toward a live hardware format.
    public func prewarm() {
        guard !running else { return }
        configureVoiceProcessing()
        engine.prepare()
        log.info("Audio pre-warmed")
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

    /// Installs the tap **and** starts the engine, converting any Obj-C
    /// `NSException` raised by AVFAudio into a Swift error. This is the crux of the
    /// crash fix: `-[AVAudioNode installTapOnBus:...]` reports failure by *raising*,
    /// and a Swift `do/catch` cannot catch that — the runtime `abort()`s and the
    /// menu-bar app vanishes. Wrapping the call in `VeloRunCatchingNSException`
    /// (an Obj-C `@try/@catch`) turns the abort into a throw the caller survives.
    private func installTapAndStart() throws {
        let input = engine.inputNode
        // Never install two taps on the same bus. A leftover tap from a session
        // that errored out (or a raced config-change re-tap) makes installTap raise
        // "already installed"; `removeTap` is a safe no-op when none is present.
        input.removeTap(onBus: 0)

        // Read the live hardware format. After idle it can transiently be 0 Hz /
        // 0 ch (input hardware still waking). Rather than reset+reread in-place
        // here — which would tear down the voice-processing IO unit we just built —
        // we throw and let start()'s retry loop settle and try again on a fresh
        // cold engine. Installing a tap with a 0 Hz format raises an uncatchable
        // Obj-C NSException, so validating first is load-bearing.
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            log.error("Input format invalid (\(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch) — hardware still waking")
            throw AudioCaptureError.invalidInputFormat
        }

        // The block MUST be `@Sendable` (non-isolated). AVAudioEngine invokes it on
        // its realtime audio thread; a closure inheriting this method's @MainActor
        // isolation would trap (SIGTRAP) when it runs off-main. Everything touched
        // synchronously is nonisolated; actor-isolated work hops via Task{@MainActor}.
        if let nsError = VeloRunCatchingNSException({
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable [weak self] buffer, _ in
                let rms = Self.rms(of: buffer)
                // The engine may recycle `buffer` once this block returns, so copy
                // it before handing it to an async task on the main actor.
                guard let copy = Self.copy(buffer) else { return }
                // `copy` is a freshly-allocated, uniquely-owned buffer used nowhere
                // else, so handing it to the main actor is race-free.
                nonisolated(unsafe) let handoff = copy
                Task { @MainActor [weak self] in
                    self?.publish(rms: rms, buffer: handoff)
                }
            }
        }) {
            log.error("installTap raised NSException: \(nsError.localizedDescription, privacy: .public)")
            throw AudioCaptureError.tapInstallFailed(nsError.localizedDescription)
        }

        // `engine.start()` normally throws a Swift error, but can also raise an
        // Obj-C NSException in edge cases — wrap it the same way. Capture any Swift
        // error thrown inside the (non-throwing) Obj-C block and rethrow it after.
        var swiftStartError: Error?
        if let nsError = VeloRunCatchingNSException({
            do { try self.engine.start() } catch { swiftStartError = error }
        }) {
            input.removeTap(onBus: 0)
            log.error("engine.start raised NSException: \(nsError.localizedDescription, privacy: .public)")
            throw AudioCaptureError.engineStartFailed(nsError.localizedDescription)
        }
        if let swiftStartError {
            input.removeTap(onBus: 0)
            throw swiftStartError
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
            // Exception-safe: converts any AVFAudio NSException into a Swift error
            // instead of aborting the process — this re-tap fires right after our
            // own engine.start(), so a raise here was a prime menu-bar-death path.
            try installTapAndStart()
        } catch {
            // Don't crash on a bad re-tap: mark ourselves stopped so the next Fn
            // press does a clean cold start instead of assuming we're still live.
            log.error("Failed to re-tap after config change: \(String(describing: error), privacy: .public)")
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
