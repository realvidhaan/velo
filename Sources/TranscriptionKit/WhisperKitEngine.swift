import Foundation
import AVFoundation
import WhisperKit
import os

/// On-device speech-to-text via **WhisperKit** (Whisper on CoreML/ANE) — the
/// offline, fully-private fallback when the Groq cloud engine isn't available.
/// The model (~600 MB, `large-v3-turbo`) downloads once and is cached.
///
/// Batch, not streaming: audio is accumulated as 16 kHz mono PCM while the
/// hotkey is held, then transcribed on release. Whisper runs faster than real
/// time on Apple Silicon, so short dictations return promptly.
public final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    public let displayName = "WhisperKit (on-device)"
    /// Default model folder in `argmaxinc/whisperkit-coreml`. Turbo keeps ~99%
    /// of large-v3 accuracy at several times the speed.
    public static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"

    private let holder: WhisperKitHolder
    private let language: String?
    private let trimSilence: Bool

    public init(model: String = WhisperKitEngine.defaultModel, locale: Locale = .current, trimSilence: Bool = true) {
        self.holder = WhisperKitHolder(model: model)
        self.language = locale.language.languageCode?.identifier
        self.trimSilence = trimSilence
    }

    /// Downloads (if needed) and loads the model. Slow on first run — call it
    /// from an explicit setup step, not eagerly on launch.
    public func prepare() async throws {
        try await holder.load()
    }

    /// Whether the model is already downloaded + loaded (no network/heavy work).
    public func isReady() async -> Bool {
        holder.isLoaded()
    }

    public func makeSession(contextualStrings: [String]) async throws -> any TranscriptionSession {
        // Bias on-device Whisper toward dictionary terms via an example-style
        // prompt (tokenized into `promptTokens` inside the holder).
        WhisperKitSession(holder: holder, language: language, biasPrompt: BiasPrompt.build(terms: contextualStrings), trimSilence: trimSilence)
    }

    /// Best-effort check for whether the model is already downloaded, so the
    /// `.auto` chain can include the on-device engine *without* risking a
    /// surprise ~600 MB download on a transient cloud failure. Mirrors
    /// WhisperKit's default HuggingFace layout:
    /// `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>`,
    /// checking for the compiled CoreML encoder that marks a complete download.
    public static func isModelInstalled(model: String = WhisperKitEngine.defaultModel) -> Bool {
        guard let docs = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return false }
        let encoder = docs
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(model)
            .appendingPathComponent("AudioEncoder.mlmodelc")
        return FileManager.default.fileExists(atPath: encoder.path)
    }
}

/// Owns the non-Sendable `WhisperKit` instance and caches it across sessions.
///
/// Modelled as an `@unchecked Sendable` class rather than an `actor`: WhisperKit
/// is a non-Sendable `open class` whose `transcribe(...)` is a `nonisolated
/// async` method. It therefore can't be returned from a `Task` or held by an
/// actor without tripping Swift 6's region checker — the library expects to be
/// used from a single, non-isolated call site that manages its own concurrency
/// internally. `@unchecked Sendable` is our assertion that we do exactly that:
/// FlowClone runs one hold-to-talk session at a time, so loads and
/// transcriptions never overlap.
final class WhisperKitHolder: @unchecked Sendable {
    private let model: String
    private var kit: WhisperKit?

    init(model: String) { self.model = model }

    func isLoaded() -> Bool { kit != nil }

    /// Lazily loads (and downloads on first run) the model, caching the instance.
    private func instance() async throws -> WhisperKit {
        if let kit { return kit }
        let loaded = try await WhisperKit(
            WhisperKitConfig(model: model, prewarm: true, load: true, download: true)
        )
        kit = loaded
        return loaded
    }

    func load() async throws { _ = try await instance() }

    func transcribe(_ samples: [Float], language: String?, biasPrompt: String?) async throws -> String {
        let kit = try await instance()
        var options = DecodingOptions(language: language)
        // Tokenize the biasing phrase into promptTokens. WhisperKit truncates to
        // its token budget and strips special tokens internally (TextDecoder).
        if let biasPrompt, let tokenizer = kit.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + biasPrompt)
            options.usePrefillPrompt = true
        }
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class WhisperKitSession: TranscriptionSession, @unchecked Sendable {
    private let converter = PCMConverter()
    private var samples: [Float] = []
    private let holder: WhisperKitHolder
    private let language: String?
    private let biasPrompt: String?
    private let trimSilence: Bool

    init(holder: WhisperKitHolder, language: String?, biasPrompt: String? = nil, trimSilence: Bool = true) {
        self.holder = holder
        self.language = language
        self.biasPrompt = biasPrompt
        self.trimSilence = trimSilence
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        samples.append(contentsOf: converter.append(buffer))
    }

    func finish() async throws -> String {
        guard !samples.isEmpty else { return "" }
        let pcm = trimSilence ? VoiceActivityTrimmer.trimSilence(samples) : samples
        return try await holder.transcribe(pcm, language: language, biasPrompt: biasPrompt)
    }

    func cancel() async {
        samples = []
    }
}
