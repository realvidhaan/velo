import Foundation
import WhisperKit

/// Trims dead air from a captured utterance before transcription. Leading and
/// trailing silence is the biggest trigger for Whisper hallucinations (the model
/// invents text for silence) and it inflates latency, so removing it is a cheap
/// accuracy + speed win.
///
/// Reuses WhisperKit's built-in `EnergyVAD` (no extra dependency, no model
/// download). Deliberately conservative: it only trims *before the first* and
/// *after the last* detected speech, keeping every internal pause intact — so it
/// can never clip a word out of the middle of a sentence.
public enum VoiceActivityTrimmer {
    /// - Parameters:
    ///   - samples: 16 kHz mono Float32 PCM. Expected to be **gain-normalized
    ///     already** (see `GainNormalizer`) so a whisper reads as normal-level
    ///     speech by the time the energy gate looks at it.
    ///   - paddingSeconds: kept on each side of speech so onsets/offsets aren't
    ///     clipped. Widened for whisper safety — soft consonants (/f/, /s/, /h/)
    ///     trail off gradually and a tight pad shears them.
    ///   - energyThreshold: RMS gate handed to `EnergyVAD`. Deliberately far below
    ///     the WhisperKit default of 0.02 (~−34 dBFS): a whisper — even after
    ///     normalization — lives only a little above room tone, so a high gate
    ///     erases it. 0.005 (~−46 dBFS) keeps soft speech while still discarding
    ///     dead air. Nearby-talker rejection is handled upstream (VP-IO +
    ///     proximity), not here.
    public static func trimSilence(
        _ samples: [Float],
        sampleRate: Int = 16_000,
        paddingSeconds: Float = 0.2,
        energyThreshold: Float = 0.005
    ) -> [Float] {
        // Too short to bother (and avoids trimming a legitimately brief word).
        guard samples.count > sampleRate / 5 else { return samples }

        let vad = EnergyVAD(sampleRate: sampleRate, energyThreshold: energyThreshold)
        let chunks = vad.calculateActiveChunks(in: samples)
        // All silence (or VAD found nothing) → leave untouched rather than return
        // an empty buffer.
        guard let first = chunks.first, let last = chunks.last else { return samples }

        let pad = Int(paddingSeconds * Float(sampleRate))
        let start = max(0, first.startIndex - pad)
        let end = min(samples.count, last.endIndex + pad)
        guard start < end, (start > 0 || end < samples.count) else { return samples }
        return Array(samples[start..<end])
    }
}
