import Foundation
import AVFoundation
import Speech
import os

/// On-device streaming STT using Apple's `SpeechAnalyzer` (macOS 26+). Audio is
/// analyzed as it streams in during the hold, so on key release only the tail
/// needs finalizing — keeping post-release latency low.
public final class SpeechAnalyzerEngine: TranscriptionEngine {
    public let displayName = "Apple SpeechAnalyzer (on-device)"
    private let locale: Locale
    private let log = Logger(subsystem: "com.flowclone.app", category: "STT")

    public init(locale: Locale = Locale.current) {
        self.locale = locale
    }

    private func makeTranscriber() -> SpeechTranscriber {
        // No volatile results: we consume finalized segments and concatenate.
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
    }

    public func prepare() async throws {
        try await Self.ensureModelInstalled(for: makeTranscriber(), log: log)
    }

    public func makeSession(contextualStrings: [String]) async throws -> any TranscriptionSession {
        let transcriber = makeTranscriber()
        try await Self.ensureModelInstalled(for: transcriber, log: log)
        return try await SpeechAnalyzerSession(transcriber: transcriber, contextualStrings: contextualStrings)
    }

    /// Downloads and installs the speech model for `transcriber`'s locale if
    /// needed. Throws `.localeUnsupported` when the locale isn't available.
    static func ensureModelInstalled(for transcriber: SpeechTranscriber, log: Logger) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            throw TranscriptionError.localeUnsupported
        case .supported, .downloading:
            log.info("Downloading speech model for locale…")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        @unknown default:
            return
        }
    }
}

/// A single utterance driven by `SpeechAnalyzer`. Not an actor: `feed` must be
/// callable synchronously from the audio tap. Internal mutable state (the format
/// converter) is only touched from `feed`, which the caller serializes.
final class SpeechAnalyzerSession: TranscriptionSession, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let resultsTask: Task<String, Error>
    private let analyzerFormat: AVAudioFormat?

    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    init(transcriber: SpeechTranscriber, contextualStrings: [String]) async throws {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = continuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: contextualStrings]
            try await analyzer.setContext(context)
        }

        // Accumulate finalized segments into the full transcript.
        self.resultsTask = Task {
            var accumulated = AttributedString()
            for try await result in transcriber.results {
                accumulated.append(result.text)
            }
            return String(accumulated.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // start(inputSequence:) returns promptly; analysis proceeds as we yield.
        try await analyzer.start(inputSequence: stream)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let target = analyzerFormat else {
            inputContinuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if let converted = convert(buffer, to: target) {
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func finish() async throws -> String {
        inputContinuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await resultsTask.value
    }

    func cancel() async {
        inputContinuation.finish()
        await analyzer.cancelAndFinishNow()
        resultsTask.cancel()
    }

    // MARK: Format conversion

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }

        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterInputFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        // The input block is invoked synchronously by `convert`, so this shared
        // state is safe despite the @Sendable signature.
        nonisolated(unsafe) let inputBuffer = buffer
        nonisolated(unsafe) var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        if status == .error { return nil }
        return output
    }
}
