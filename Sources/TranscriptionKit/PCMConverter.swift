import AVFoundation

/// Streams mic buffers into **16 kHz mono Float32** samples — the format every
/// Whisper engine (Groq cloud, WhisperKit on-device) expects. Holds a single
/// `AVAudioConverter` so the resampler's filter state stays continuous across
/// buffers (a fresh converter per buffer would introduce boundary artifacts).
///
/// Not an actor: `append` is called synchronously from the audio tap, which the
/// caller serializes (one utterance at a time).
final class PCMConverter: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    /// Converts one input buffer to 16 kHz mono float samples (downmixing and
    /// resampling as needed). Returns an empty array on conversion failure.
    func append(_ buffer: AVAudioPCMBuffer) -> [Float] {
        if buffer.format == targetFormat {
            return Self.samples(from: buffer)
        }
        if converter == nil || inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            inputFormat = buffer.format
        }
        guard let converter else { return [] }

        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return [] }

        // The input block is invoked synchronously; supply the buffer exactly once.
        nonisolated(unsafe) let input = buffer
        nonisolated(unsafe) var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error { return [] }
        return Self.samples(from: output)
    }

    /// Extracts channel-0 float samples from a mono float buffer.
    static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }
}
