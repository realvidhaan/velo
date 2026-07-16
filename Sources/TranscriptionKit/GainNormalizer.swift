import Foundation

/// Boosts quiet/whispered audio toward a consistent level before it reaches the
/// speech model. This is the highest-leverage whisper fix: whispered speech
/// reaches the mic at a very low amplitude, and Whisper's dominant failure on it
/// is *low input level*, not the whisper timbre. Two concrete wins:
///  - **Quantization:** the Groq path encodes to 16-bit PCM (`WAVEncoder`); a
///    peak of ~0.005 would land near Int16 ±160, throwing away most of the
///    detail. Normalizing to ~0.9 first preserves it.
///  - **Consistency:** the model sees a stable level regardless of how softly the
///    user spoke.
///
/// Engine-independent and deterministic, so it helps even when Apple's voice
/// processing (AGC) is off or over-suppresses a genuine whisper. Peak-based (not
/// RMS) so the result never clips, gain-capped so we don't blow up the noise
/// floor, and skipped entirely on pure silence/noise so we never amplify a room.
public enum GainNormalizer {
    /// - Parameters:
    ///   - targetPeak: peak the loudest sample is scaled toward (< 1 → no clip).
    ///   - maxGain: hard ceiling on the boost, so a near-silent/noisy clip isn't
    ///     amplified into a wall of noise.
    ///   - noiseFloor: if the whole clip peaks below this, it's silence/noise —
    ///     leave it untouched.
    public static func normalize(
        _ samples: [Float],
        targetPeak: Float = 0.9,
        maxGain: Float = 20,
        noiseFloor: Float = 0.003
    ) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var peak: Float = 0
        for sample in samples { peak = max(peak, abs(sample)) }

        // Nothing but silence/noise — don't amplify a room.
        guard peak > noiseFloor else { return samples }

        // Only ever boost (gain ≥ 1); never attenuate already-loud speech. Cap so
        // a very quiet clip doesn't get slammed to the ceiling.
        let gain = min(max(targetPeak / peak, 1.0), maxGain)
        guard gain > 1.0001 else { return samples }

        return samples.map { $0 * gain }
    }
}
