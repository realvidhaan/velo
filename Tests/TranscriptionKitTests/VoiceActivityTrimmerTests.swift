import XCTest
@testable import TranscriptionKit

final class VoiceActivityTrimmerTests: XCTestCase {
    private let sr = 16_000

    /// A tone burst (speech stand-in) surrounded by silence.
    private func signal(leadingSilence: Double, speech: Double, trailingSilence: Double) -> [Float] {
        func silence(_ seconds: Double) -> [Float] { Array(repeating: 0, count: Int(Double(sr) * seconds)) }
        func tone(_ seconds: Double) -> [Float] {
            let n = Int(Double(sr) * seconds)
            return (0..<n).map { 0.5 * sin(2 * .pi * 440 * Float($0) / Float(sr)) }
        }
        return silence(leadingSilence) + tone(speech) + silence(trailingSilence)
    }

    func testTrimsLeadingAndTrailingSilence() {
        let samples = signal(leadingSilence: 1.0, speech: 1.0, trailingSilence: 1.0)
        let trimmed = VoiceActivityTrimmer.trimSilence(samples, sampleRate: sr)
        // Should drop most of the 2s of silence, keeping ~1s of speech + padding.
        XCTAssertLessThan(trimmed.count, samples.count)
        XCTAssertGreaterThan(trimmed.count, sr) // more than 1s (speech + padding) retained
        XCTAssertLessThan(trimmed.count, samples.count - sr) // at least ~1s of silence removed
    }

    func testPreservesSpeechSamples() {
        let samples = signal(leadingSilence: 0.5, speech: 0.5, trailingSilence: 0.5)
        let trimmed = VoiceActivityTrimmer.trimSilence(samples, sampleRate: sr)
        // Peak amplitude (the tone) must survive the trim.
        XCTAssertEqual(trimmed.map { abs($0) }.max() ?? 0, 0.5, accuracy: 0.05)
    }

    func testAllSilenceLeftUntouched() {
        let samples = Array(repeating: Float(0), count: sr) // 1s pure silence
        XCTAssertEqual(VoiceActivityTrimmer.trimSilence(samples, sampleRate: sr).count, samples.count)
    }

    func testShortClipUntouched() {
        let samples = Array(repeating: Float(0.1), count: sr / 10) // 0.1s
        XCTAssertEqual(VoiceActivityTrimmer.trimSilence(samples, sampleRate: sr).count, samples.count)
    }

    /// A low-amplitude tone burst (whisper stand-in) whose RMS sits above the new
    /// 0.005 gate but well below the old 0.02 default. The old threshold would have
    /// treated the whole clip as silence and — via the all-silence guard — returned
    /// it untouched, so the leading/trailing dead air would ride into the model.
    /// The whisper-safe threshold must instead *detect* the soft burst: trim the
    /// surrounding silence while preserving the quiet speech (peak and duration).
    func testKeepsQuietWhisperLevelSpeech() {
        func silence(_ seconds: Double) -> [Float] { Array(repeating: 0, count: Int(Double(sr) * seconds)) }
        // ~0.012 peak → ~0.0085 RMS: a whisper, not silence, but under 0.02.
        let n = Int(Double(sr) * 0.6)
        let quiet = (0..<n).map { 0.012 * sin(2 * .pi * 440 * Float($0) / Float(sr)) }
        let samples = silence(0.5) + quiet + silence(0.5)

        let trimmed = VoiceActivityTrimmer.trimSilence(samples, sampleRate: sr)

        // Detected the soft speech and removed dead air (not the all-silence no-op).
        XCTAssertLessThan(trimmed.count, samples.count)
        // The quiet speech itself must survive — peak intact, ~0.6s retained.
        XCTAssertEqual(trimmed.map { abs($0) }.max() ?? 0, 0.012, accuracy: 0.002)
        XCTAssertGreaterThanOrEqual(trimmed.count, n)
    }

    func testNoInternalClipping() {
        // Speech, gap, speech — the internal gap must be preserved (only ends trimmed).
        let s = signal(leadingSilence: 1.0, speech: 0.5, trailingSilence: 0.0)
            + Array(repeating: Float(0), count: sr / 2) // 0.5s internal gap
            + signal(leadingSilence: 0.0, speech: 0.5, trailingSilence: 1.0)
        let trimmed = VoiceActivityTrimmer.trimSilence(s, sampleRate: sr)
        // Roughly: 0.5 + 0.5(gap) + 0.5 speech = ~1.5s kept + padding, well above 1.2s.
        XCTAssertGreaterThan(trimmed.count, Int(Double(sr) * 1.2))
    }
}
