import Foundation

/// A single-word substitution the user made when editing dictated text —
/// e.g. they changed "vidon" to "Vidhaan". These become personal-dictionary
/// suggestions.
public struct Substitution: Equatable, Hashable, Sendable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Word-level diff between the text Velo injected and the text the user
/// ended up with, extracting 1-word→1-word substitutions (the shape that maps
/// cleanly to a dictionary rule). Multi-word edits are ignored — they're
/// usually genuine rewrites, not vocabulary corrections.
public enum TokenDiff {
    public static func substitutions(from injected: String, to corrected: String) -> [Substitution] {
        let a = tokenize(injected)
        let b = tokenize(corrected)
        guard !a.isEmpty, !b.isEmpty else { return [] }

        // Longest common subsequence over words, then walk the tables to find
        // aligned replace operations.
        let lcs = lcsTable(a, b)
        var i = a.count, j = b.count
        var ops: [(String?, String?)] = []   // (removed, added) in reverse
        while i > 0 && j > 0 {
            if a[i - 1].lower == b[j - 1].lower {
                ops.append((nil, nil))   // match
                i -= 1; j -= 1
            } else if lcs[i - 1][j] >= lcs[i][j - 1] {
                ops.append((a[i - 1].original, nil))  // removed a[i-1]
                i -= 1
            } else {
                ops.append((nil, b[j - 1].original))  // added b[j-1]
                j -= 1
            }
        }
        while i > 0 { ops.append((a[i - 1].original, nil)); i -= 1 }
        while j > 0 { ops.append((nil, b[j - 1].original)); j -= 1 }
        ops.reverse()

        // Group each "change block" between matches. A block that removed
        // exactly one word and added exactly one word is a 1:1 substitution
        // (regardless of the order the walk emitted them).
        var result: [Substitution] = []
        var removed: [String] = []
        var added: [String] = []
        func flush() {
            if removed.count == 1, added.count == 1 {
                result.append(Substitution(from: removed[0], to: added[0]))
            }
            removed.removeAll()
            added.removeAll()
        }
        for (r, a) in ops {
            if r == nil, a == nil {
                flush()   // a matched word ends the current change block
            } else {
                if let r { removed.append(r) }
                if let a { added.append(a) }
            }
        }
        flush()
        return result.filter { $0.from.lowercased() != $0.to.lowercased() }
    }

    private struct Token { let original: String; let lower: String }

    private static func tokenize(_ text: String) -> [Token] {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }
            .map { word in
                let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                return Token(original: String(word), lower: trimmed.lowercased())
            }
            .filter { !$0.lower.isEmpty }
    }

    /// Caller (`substitutions`) guarantees both arrays are non-empty.
    private static func lcsTable(_ a: [Token], _ b: [Token]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1].lower == b[j - 1].lower {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        return table
    }
}
