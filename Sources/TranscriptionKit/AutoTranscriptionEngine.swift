import Foundation
import AVFoundation
import os

/// Tries an ordered chain of engines, falling back to the next when one is
/// unavailable — no API key, a network error, an offline cloud call. This is
/// what powers the `.auto` STT setting: Groq Whisper (cloud) → WhisperKit
/// (on-device, only if its model is installed) → Apple SpeechAnalyzer.
///
/// Because the Whisper engines are *batch* (they transcribe on release, not
/// streaming), the composite session simply retains the captured audio buffers
/// and replays them into whichever engine succeeds. Each engine builds its own
/// `PCMConverter`, so replaying the same buffers into a fresh session is
/// correct.
public struct AutoTranscriptionEngine: TranscriptionEngine {
    public let displayName = "Automatic"
    private let engines: [any TranscriptionEngine]

    public init(engines: [any TranscriptionEngine]) {
        self.engines = engines
    }

    /// Prepares every engine in the chain so each is ready to be the fallback.
    /// Callers gate which engines enter the chain (e.g. only an installed
    /// WhisperKit) so `prepare()` never triggers a surprise download here.
    public func prepare() async throws {
        for engine in engines {
            try? await engine.prepare()
        }
    }

    public func makeSession(contextualStrings: [String]) async throws -> any TranscriptionSession {
        AutoSession(engines: engines, contextualStrings: contextualStrings)
    }
}

final class AutoSession: TranscriptionSession, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.flowclone.app", category: "AutoSTT")
    private let engines: [any TranscriptionEngine]
    private let contextualStrings: [String]
    /// Retained mic buffers, replayed into whichever engine wins. Short
    /// dictations only, so the memory cost is bounded.
    private var buffers: [AVAudioPCMBuffer] = []

    init(engines: [any TranscriptionEngine], contextualStrings: [String]) {
        self.engines = engines
        self.contextualStrings = contextualStrings
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        buffers.append(buffer)
    }

    func finish() async throws -> String {
        var lastError: Error?
        for engine in engines {
            do {
                let session = try await engine.makeSession(contextualStrings: contextualStrings)
                for buffer in buffers { session.feed(buffer) }
                let text = try await session.finish()
                // A blank result (e.g. silence) is a valid answer — return it and
                // don't waste the next engine on it. Only *errors* fall through.
                return text
            } catch {
                Self.log.warning("STT engine \(engine.displayName, privacy: .public) failed, falling back: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return ""
    }

    func cancel() async {
        buffers = []
    }
}
