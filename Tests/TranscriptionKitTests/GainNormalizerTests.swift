import XCTest
@testable import TranscriptionKit

final class GainNormalizerTests: XCTestCase {
    private func peak(_ s: [Float]) -> Float { s.map { abs($0) }.max() ?? 0 }

    func testBoostsQuietSignalTowardTarget() {
        // Quiet whisper-level signal (peak 0.05) → boosted toward 0.9.
        let quiet: [Float] = [0.05, -0.04, 0.03, -0.05, 0.02]
        let out = GainNormalizer.normalize(quiet)
        XCTAssertEqual(peak(out), 0.9, accuracy: 0.01)
    }

    func testCapsGainForVeryQuietClip() {
        // Peak 0.01 wants ~90× to reach 0.9; capped at 20× → peak 0.2.
        let veryQuiet: [Float] = [0.01, -0.008, 0.01, -0.009]
        let out = GainNormalizer.normalize(veryQuiet, maxGain: 20)
        XCTAssertEqual(peak(out), 0.2, accuracy: 0.005)
    }

    func testLeavesSilenceOrNoiseUntouched() {
        // Below the noise floor → not amplified.
        let noise: [Float] = [0.002, -0.001, 0.0015, -0.002]
        XCTAssertEqual(GainNormalizer.normalize(noise), noise)
    }

    func testDoesNotAttenuateLoudSignal() {
        // Already near full scale → left as-is (only boosts, never reduces).
        let loud: [Float] = [0.95, -0.9, 0.85, -0.95]
        XCTAssertEqual(GainNormalizer.normalize(loud), loud)
    }

    func testNeverClips() {
        let signal: [Float] = [0.3, -0.25, 0.2, -0.31]
        let out = GainNormalizer.normalize(signal)
        XCTAssertLessThanOrEqual(peak(out), 0.9 + 1e-5)
    }

    func testEmptyInput() {
        XCTAssertEqual(GainNormalizer.normalize([]), [])
    }

    func testPreservesShapeAndSampleCount() {
        let signal: [Float] = [0.05, -0.05, 0.025, -0.05]
        let out = GainNormalizer.normalize(signal)
        XCTAssertEqual(out.count, signal.count)
        // Uniform gain → sign pattern and relative ratios preserved.
        XCTAssertEqual(out[0] / out[2], signal[0] / signal[2], accuracy: 1e-4)
    }
}
