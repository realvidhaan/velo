import Foundation

/// Deterministic, offline text polish. Two roles:
///   1. The **fast path** for very short utterances (skips the LLM so "yes" /
///      "sounds good" feel instant).
///   2. The **terminal fallback** when every LLM engine fails — nicer than
///      injecting the raw transcript.
///
/// Conservative by design: it strips standalone fillers, collapses immediate
/// word repeats (stutters), writes small standalone numbers as digits,
/// capitalizes, and adds terminal punctuation. It never reorders or rewrites
/// meaning — the LLM cleanup pass handles anything nuanced.
public enum LocalPolish {
    /// Standalone filler words removed anywhere in the text.
    static let fillers: Set<String> = ["um", "uh", "uhm", "erm", "er", "ah", "hmm", "mm", "mhm"]
    /// Fillers removed only when they lead the utterance (too risky mid-sentence,
    /// e.g. "I like it").
    static let leadingFillers: [String] = ["like", "so", "you know", "i mean", "well", "basically"]

    public static func wordCount(_ text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    /// Whether an utterance is short enough to skip the LLM. Kept small (≤2) so
    /// anything sentence-shaped still gets the LLM's numbers/punctuation cleanup;
    /// only quick acknowledgements ("yes", "sounds good") take the fast path.
    public static func isShort(_ text: String) -> Bool {
        wordCount(text) <= 2
    }

    public static func polish(_ text: String) -> String {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return "" }

        // Drop a leading filler word/phrase (case-insensitive), once.
        for phrase in leadingFillers {
            if let range = leadingRange(of: phrase, in: working) {
                working.removeSubrange(range)
                working = working.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        var words = working.split(separator: " ").map(String.init)
        // Remove standalone hard fillers anywhere.
        words.removeAll { fillers.contains(bareWord($0)) }
        // Collapse immediate duplicate words (stutters: "the the" -> "the").
        words = collapseRepeats(words)
        // Write small standalone numbers as digits ("ten" -> "10").
        words = digitizeNumbers(words)
        working = words.joined(separator: " ")
        guard !working.isEmpty else { return "" }

        working = capitalizingFirstLetter(working)

        // Add terminal punctuation for sentence-length utterances.
        if wordCount(working) >= 3, let last = working.last, !".!?".contains(last) {
            working.append(".")
        }
        return working
    }

    // MARK: Helpers

    /// A word lowercased and stripped of surrounding punctuation, for matching.
    private static func bareWord(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    private static func collapseRepeats(_ words: [String]) -> [String] {
        var result: [String] = []
        for word in words {
            if let prev = result.last, bareWord(prev) == bareWord(word), !bareWord(word).isEmpty {
                continue
            }
            result.append(word)
        }
        return result
    }

    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Converts standalone number words 0–99 to digits, combining "twenty five"
    /// into "25". Deliberately skips hundred/thousand and idiomatic uses — those
    /// are left to the LLM pass. Punctuation attached to a word is preserved.
    private static func digitizeNumbers(_ words: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < words.count {
            let (core, trailing) = splitTrailingPunct(words[i])
            let key = core.lowercased()
            if let t = tens[key] {
                // Look ahead for a ones word to combine (e.g. "twenty" "five").
                if i + 1 < words.count {
                    let (nextCore, nextTrailing) = splitTrailingPunct(words[i + 1])
                    if let o = ones[nextCore.lowercased()], o < 10 {
                        result.append("\(t + o)\(nextTrailing)")
                        i += 2
                        continue
                    }
                }
                result.append("\(t)\(trailing)")
            } else if let o = ones[key] {
                result.append("\(o)\(trailing)")
            } else {
                result.append(words[i])
            }
            i += 1
        }
        return result
    }

    /// Splits trailing punctuation off a word: "ten," -> ("ten", ",").
    private static func splitTrailingPunct(_ word: String) -> (core: String, trailing: String) {
        guard let idx = word.lastIndex(where: { !CharacterSet.punctuationCharacters.contains($0.unicodeScalars.first!) }) else {
            return (word, "")
        }
        let core = String(word[...idx])
        let trailing = String(word[word.index(after: idx)...])
        return (core, trailing)
    }

    private static func leadingRange(of phrase: String, in text: String) -> Range<String.Index>? {
        let lowered = text.lowercased()
        let target = phrase.lowercased() + " "
        guard lowered.hasPrefix(target) else { return nil }
        return text.startIndex..<text.index(text.startIndex, offsetBy: phrase.count)
    }

    private static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
