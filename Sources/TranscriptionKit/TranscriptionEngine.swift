import Foundation
import AVFoundation

public enum TranscriptionError: Error, Equatable {
    case localeUnsupported
    case modelUnavailable
    case engineUnavailable(String)
}

/// A speech-to-text engine. Implementations are swappable between on-device
/// (`SpeechAnalyzerEngine`) and cloud (Groq Whisper, added later). Kept behind a
/// protocol so the app never depends on a specific provider.
public protocol TranscriptionEngine: Sendable {
    var displayName: String { get }

    /// Ensure the engine is ready (models installed, etc.). May download.
    func prepare() async throws

    /// Begin a new utterance. `contextualStrings` biases recognition toward the
    /// user's personal-dictionary terms (names, jargon).
    func makeSession(contextualStrings: [String]) async throws -> any TranscriptionSession
}

/// One utterance. Audio is fed while the hotkey is held; `finish()` finalizes on
/// release and returns the transcript.
public protocol TranscriptionSession: AnyObject, Sendable {
    /// Feed a captured audio buffer. The session converts formats as needed, so
    /// callers can pass buffers straight from the mic tap.
    func feed(_ buffer: AVAudioPCMBuffer)

    /// Stop input, finalize, and return the full transcript.
    func finish() async throws -> String

    /// Abort without producing a transcript.
    func cancel() async
}
