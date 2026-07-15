import Foundation

/// A term surfaced from the user's dictation history as a likely dictionary
/// candidate, with how often it appeared.
public struct VocabCandidate: Equatable, Sendable {
    public let term: String
    public let count: Int
    public init(term: String, count: Int) {
        self.term = term
        self.count = count
    }
}

/// Mines dictation history for distinctive words the user says repeatedly but
/// hasn't added to their dictionary — the "auto-learn vocabulary" loop Wispr Flow
/// runs. The key move (Wispr's explicit rule) is **filtering common everyday
/// words** so only proper nouns / jargon / product names bubble up. This is pure,
/// deterministic, and local — no ML, no network.
public enum VocabMiner {
    /// - Parameters:
    ///   - transcripts: recent raw transcripts (most useful signal is the raw
    ///     STT text, before cleanup).
    ///   - existing: already-known terms (lowercased) to exclude.
    ///   - minCount: how many times a term must recur to be suggested.
    public static func candidates(
        from transcripts: [String],
        existing: Set<String>,
        minCount: Int = 3,
        stopwords: Set<String> = VocabMiner.defaultStopwords
    ) -> [VocabCandidate] {
        var counts: [String: (display: String, n: Int)] = [:]
        for text in transcripts {
            for token in tokenize(text) {
                let key = token.lowercased()
                guard key.count >= 3, !stopwords.contains(key), !existing.contains(key) else { continue }
                var entry = counts[key] ?? (display: token, n: 0)
                // Prefer a capitalized/mixed-case spelling as the display form —
                // that's the proper-noun signal we most want to preserve.
                if isDistinctive(token) && !isDistinctive(entry.display) { entry.display = token }
                entry.n += 1
                counts[key] = entry
            }
        }
        return counts.values
            .filter { $0.n >= minCount && isDistinctive($0.display) }
            .map { VocabCandidate(term: $0.display, count: $0.n) }
            .sorted { $0.count == $1.count ? $0.term < $1.term : $0.count > $1.count }
    }

    /// Splits on whitespace and trims surrounding punctuation, but preserves
    /// word-internal characters so "useState", "GitHub", and "v3-turbo" survive.
    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}…")) }
            .filter { !$0.isEmpty }
    }

    /// "Distinctive" = looks like a proper noun / identifier rather than an
    /// everyday word: has any uppercase letter, contains a digit or internal
    /// hyphen, or is unusually long.
    static func isDistinctive(_ token: String) -> Bool {
        if token.contains(where: { $0.isUppercase }) { return true }
        if token.contains(where: { $0.isNumber }) { return true }
        if token.dropFirst().contains("-") { return true }
        return token.count >= 9
    }

    /// A compact set of the most common English words plus dictation fillers, so
    /// they never get suggested as vocabulary.
    public static let defaultStopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "her", "was",
        "one", "our", "out", "day", "get", "has", "him", "his", "how", "man", "new", "now",
        "old", "see", "two", "way", "who", "boy", "did", "its", "let", "put", "say", "she",
        "too", "use", "that", "this", "with", "have", "from", "they", "know", "want", "been",
        "good", "much", "some", "time", "very", "when", "come", "here", "just", "like", "long",
        "make", "many", "over", "such", "take", "than", "them", "well", "were", "what", "your",
        "about", "would", "there", "their", "which", "could", "other", "these", "thing", "think",
        "going", "really", "actually", "basically", "kind", "sort", "yeah", "okay", "gonna",
        "wanna", "stuff", "little", "because", "should", "people", "right", "still", "back",
        "even", "also", "then", "than", "into", "only", "most", "more", "need", "will", "said",
        "um", "uh", "erm", "hmm", "mhm", "gonna", "dunno",
    ]
}
