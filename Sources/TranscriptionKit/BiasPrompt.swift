import Foundation

/// Builds the vocabulary-biasing prompt handed to Whisper (Groq's `prompt`
/// field, WhisperKit's `promptTokens`). Two facts drive the design, both from
/// OpenAI's Whisper prompting guide and faster-whisper's implementation:
///
///  1. Whisper's prompt biases the **style and spelling** of the output toward
///     the prompt — it does *not* follow instructions. So we render terms as a
///     short natural phrase ("Vocabulary: …"), the example style OpenAI shows,
///     rather than dumping a bare comma list.
///  2. The prompt is capped at ~224 tokens and the decoder weights tokens near
///     the **end** most heavily. So we budget to ~220 tokens and place the
///     highest-priority terms **last**.
public enum BiasPrompt {
    /// Conservative ceiling below Whisper's ~224-token hard cap.
    public static let maxTokens = 220

    /// - Parameter terms: dictionary terms in priority order (most important
    ///   first — callers pass them most-recent/most-relevant first).
    /// - Returns: a biasing phrase, or nil if there's nothing to bias.
    public static func build(terms: [String], maxTokens: Int = BiasPrompt.maxTokens) -> String? {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        let prefix = "Vocabulary: "
        let suffix = "."
        var budget = maxTokens - estimateTokens(prefix + suffix)

        // Greedily admit terms in priority order (most important first) until the
        // budget is spent…
        var selected: [String] = []
        for term in cleaned {
            let cost = estimateTokens(term) + 1 // + separator
            if cost > budget { continue }        // skip an over-long term, keep trying shorter ones
            selected.append(term)
            budget -= cost
        }
        guard !selected.isEmpty else { return nil }

        // …then reverse so the highest-priority terms sit at the END, where the
        // decoder's attention weights them most.
        return prefix + selected.reversed().joined(separator: ", ") + suffix
    }

    /// Cheap token estimate (~4 chars/token) — we only need to stay safely under
    /// the cap, not count exactly.
    static func estimateTokens(_ s: String) -> Int {
        max(1, (s.count + 3) / 4)
    }
}
