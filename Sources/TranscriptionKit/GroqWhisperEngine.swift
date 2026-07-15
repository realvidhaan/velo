import Foundation
import AVFoundation
import os

/// Cloud speech-to-text via Groq's Whisper `large-v3-turbo` — the default
/// engine. Whisper is far stronger than Apple's recognizer on proper nouns,
/// jargon, and disfluent real-world dictation, and it formats numbers and
/// punctuation natively. Groq runs it at ~200× real time, so a short clip comes
/// back in a few hundred ms.
///
/// Batch, not streaming: audio is accumulated (as 16 kHz mono PCM) while the
/// hotkey is held, then uploaded as a WAV on release.
public struct GroqWhisperEngine: TranscriptionEngine {
    public let displayName = "Groq Whisper (cloud)"
    private let apiKey: String?
    private let model: String
    private let timeout: TimeInterval

    public init(apiKey: String?, model: String = "whisper-large-v3-turbo", timeout: TimeInterval = 15) {
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
    }

    /// Nothing to install — the model runs on Groq's servers.
    public func prepare() async throws {}

    public func makeSession(contextualStrings: [String]) async throws -> any TranscriptionSession {
        guard let apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.engineUnavailable("Groq API key not set")
        }
        return GroqWhisperSession(apiKey: apiKey, model: model, promptTerms: contextualStrings, timeout: timeout)
    }
}

final class GroqWhisperSession: TranscriptionSession, @unchecked Sendable {
    private let converter = PCMConverter()
    private var samples: [Float] = []
    private let apiKey: String
    private let model: String
    private let promptTerms: [String]
    private let timeout: TimeInterval

    init(apiKey: String, model: String, promptTerms: [String], timeout: TimeInterval) {
        self.apiKey = apiKey
        self.model = model
        self.promptTerms = promptTerms
        self.timeout = timeout
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        samples.append(contentsOf: converter.append(buffer))
    }

    func finish() async throws -> String {
        guard !samples.isEmpty else { return "" }
        let wav = WAVEncoder.encode(samples: samples, sampleRate: Int(PCMConverter.sampleRate))
        // The `prompt` biases Whisper toward the user's dictionary spellings.
        let prompt = promptTerms.isEmpty ? nil : promptTerms.joined(separator: ", ")
        return try await GroqTranscriptionClient.transcribe(
            wav: wav, apiKey: apiKey, model: model, prompt: prompt, timeout: timeout
        )
    }

    func cancel() async {
        samples = []
    }
}

/// Multipart upload to Groq's OpenAI-compatible transcription endpoint. Separate
/// from the JSON chat client since audio transcription is `multipart/form-data`.
enum GroqTranscriptionClient {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    static func transcribe(
        wav: Data,
        apiKey: String,
        model: String,
        prompt: String?,
        timeout: TimeInterval
    ) async throws -> String {
        let boundary = "flowclone-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(contentsOf: Array("--\(boundary)\r\n".utf8))
            body.append(contentsOf: Array("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(contentsOf: Array("\(value)\r\n".utf8))
        }
        field("model", model)
        if let prompt, !prompt.isEmpty { field("prompt", prompt) }
        field("response_format", "text")
        field("temperature", "0")
        // Audio file part.
        body.append(contentsOf: Array("--\(boundary)\r\n".utf8))
        body.append(contentsOf: Array("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(contentsOf: Array("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(contentsOf: Array("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.engineUnavailable("Groq: no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.engineUnavailable("Groq transcription HTTP \(http.statusCode): \(detail)")
        }
        // response_format=text → the body is the transcript.
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
