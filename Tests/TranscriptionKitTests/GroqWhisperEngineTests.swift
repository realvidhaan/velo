import XCTest
import AVFoundation
@testable import TranscriptionKit

/// Live cloud STT test: synthesize speech with `say`, then transcribe it through
/// the real GroqWhisperEngine (PCMConverter → WAVEncoder → multipart upload).
/// Gated on GROQ_API_KEY so CI / contributors without a key skip it.
final class GroqWhisperEngineTests: XCTestCase {
    func testTranscribeSynthesizedSpeech() async throws {
        let key = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
        try XCTSkipUnless(!key.isEmpty, "Set GROQ_API_KEY to run the live Groq Whisper test")

        let phrase = "the quick brown fox jumps over the lazy dog"
        let audioURL = try synthesize(phrase)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let engine = GroqWhisperEngine(apiKey: key)
        let transcript = try await transcribeAudioFile(audioURL, using: engine)
        print("GROQ Whisper transcript: \(transcript)")

        let normalized = transcript.lowercased()
        XCTAssertFalse(normalized.isEmpty, "empty transcript")
        XCTAssertTrue(normalized.contains("quick"), "got: \(transcript)")
        XCTAssertTrue(normalized.contains("fox"), "got: \(transcript)")
        XCTAssertTrue(normalized.contains("lazy"), "got: \(transcript)")
    }

    private func synthesize(_ text: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fc-groqstt-\(UUID().uuidString).aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "Samantha", "-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("`say` did not produce audio")
        }
        return url
    }
}

final class WAVEncoderTests: XCTestCase {
    func testHeaderAndSize() {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1]
        let data = WAVEncoder.encode(samples: samples, sampleRate: 16_000)

        // 44-byte header + 2 bytes/sample.
        XCTAssertEqual(data.count, 44 + samples.count * 2)
        XCTAssertEqual(String(bytes: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(bytes: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(bytes: data[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(bytes: data[36..<40], encoding: .ascii), "data")
    }

    func testClampsAndScales() {
        // +1.0 → Int16.max, -1.0 → -Int16.max, over-range clamps.
        let data = WAVEncoder.encode(samples: [1.0, -1.0, 2.0], sampleRate: 16_000)
        func sample(at index: Int) -> Int16 {
            let lo = UInt16(data[44 + index * 2])
            let hi = UInt16(data[44 + index * 2 + 1])
            return Int16(bitPattern: lo | (hi << 8))
        }
        XCTAssertEqual(sample(at: 0), Int16.max)
        XCTAssertEqual(sample(at: 1), -Int16.max)
        XCTAssertEqual(sample(at: 2), Int16.max) // 2.0 clamped to 1.0
    }
}
