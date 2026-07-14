import XCTest
import AVFoundation
@testable import TranscriptionKit

/// End-to-end STT test: synthesize speech with `say`, then transcribe it with
/// `SpeechAnalyzerEngine`. Gated behind FLOWCLONE_RUN_STT_TEST because it needs
/// the on-device speech model installed (a one-time download) and is slow, so
/// CI without the model stays green.
final class SpeechAnalyzerEngineTests: XCTestCase {
    func testTranscribeSynthesizedSpeech() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FLOWCLONE_RUN_STT_TEST"] == "1",
            "Set FLOWCLONE_RUN_STT_TEST=1 to run the live STT test (needs speech model)"
        )

        let phrase = "the quick brown fox jumps over the lazy dog"
        let audioURL = try synthesize(phrase)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = SpeechAnalyzerEngine(locale: Locale(identifier: "en-US"))
        let transcript = try await transcribeAudioFile(audioURL, using: engine)

        let normalized = transcript.lowercased()
        print("STT transcript: \(transcript)")
        // Recognition isn't perfect; require the distinctive keywords.
        XCTAssertTrue(normalized.contains("quick"), "got: \(transcript)")
        XCTAssertTrue(normalized.contains("fox"), "got: \(transcript)")
        XCTAssertTrue(normalized.contains("lazy"), "got: \(transcript)")
    }

    /// Uses macOS `say` to render a phrase to an audio file.
    private func synthesize(_ text: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fc-stt-\(UUID().uuidString).aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("`say` did not produce audio")
        }
        return url
    }
}
