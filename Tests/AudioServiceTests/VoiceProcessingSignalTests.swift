import XCTest
import AVFoundation
@testable import AudioService

/// Diagnostic for the "always transcribes 'Thank you'" bug: Whisper hallucinates
/// "Thank you" on *silence*, so the question is whether the capture layer is
/// delivering real signal. This measures the peak sample energy the tap sees with
/// voice processing ON vs OFF. If VP-IO yields ~silence while raw capture yields a
/// real ambient level, VP-IO is the culprit.
///
/// Gated on VELO_RUN_AUDIO_TEST=1 (needs a real mic).
final class VoiceProcessingSignalTests: XCTestCase {
    @MainActor
    private func measurePeak(voiceProcessing: Bool) async throws -> Float {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VELO_RUN_AUDIO_TEST"] == "1",
            "Set VELO_RUN_AUDIO_TEST=1 (needs mic access)"
        )
        guard AudioCaptureService.microphoneAuthorized else {
            throw XCTSkip("Microphone not authorized for the test host")
        }

        let service = AudioCaptureService()
        service.voiceProcessing = voiceProcessing

        // Track the loudest sample any buffer carried over the capture window.
        let box = PeakBox()
        service.onBuffer = { buffer in
            guard let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            var p: Float = 0
            for i in 0..<n { p = max(p, abs(ch[0][i])) }
            box.update(p)
        }

        try service.start()
        try await Task.sleep(for: .seconds(2))
        service.stop()

        let peak = box.value
        print("PEAK voiceProcessing=\(voiceProcessing): \(peak)")
        return peak
    }

    @MainActor
    func testRawCaptureHasSignal() async throws {
        let peak = try await measurePeak(voiceProcessing: false)
        XCTAssertGreaterThan(peak, 0.0001, "raw capture delivered ~silence")
    }

    @MainActor
    func testVoiceProcessingHasSignal() async throws {
        let peak = try await measurePeak(voiceProcessing: true)
        XCTAssertGreaterThan(peak, 0.0001, "voice-processing capture delivered ~silence")
    }
}

/// Thread-safe max accumulator; the tap fires on the realtime thread.
final class PeakBox: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    func update(_ p: Float) { lock.lock(); peak = max(peak, p); lock.unlock() }
    var value: Float { lock.lock(); defer { lock.unlock() }; return peak }
}
