import Foundation

/// A single deterministic substitution: any of `originals` (spoken/misheard
/// variants) → `replacement` (the canonical form). Decoupled from the SwiftData
/// model so CleanupKit doesn't depend on PersistenceKit.
public struct Replacement: Sendable, Equatable {
    public let originals: [String]
    public let replacement: String

    public init(originals: [String], replacement: String) {
        self.originals = originals
        self.replacement = replacement
    }
}

/// Applies user/learned replacement rules to a raw transcript. This is the
/// deterministic correction layer every dictation app runs **after** STT and
/// **before** the LLM cleanup pass — so the LLM sees already-corrected text and
/// can't "fix" a name back to the wrong spelling.
///
/// Matching is case-insensitive and word-boundary-anchored (so "cat" doesn't
/// hit "category"), and longer patterns are applied first so a multi-word rule
/// ("get hub" → "GitHub") isn't pre-empted by a shorter overlapping one.
public enum ReplacementRules {
    public static func apply(_ text: String, rules: [Replacement]) -> String {
        guard !text.isEmpty, !rules.isEmpty else { return text }

        // Flatten to (pattern → replacement) pairs, drop blanks, dedupe, and sort
        // longest-pattern-first to avoid partial clobbering.
        var pairs: [(pattern: String, replacement: String)] = []
        var seen = Set<String>()
        for rule in rules {
            for original in rule.originals {
                let pattern = original.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pattern.isEmpty, seen.insert(pattern.lowercased()).inserted else { continue }
                pairs.append((pattern, rule.replacement))
            }
        }
        pairs.sort { $0.pattern.count > $1.pattern.count }

        var result = text
        for (pattern, replacement) in pairs {
            result = replaceWordBounded(pattern, with: replacement, in: result)
        }
        return result
    }

    private static func replaceWordBounded(_ pattern: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        // \b anchors only work before/after word characters; guard so a pattern
        // that starts or ends with a non-word char still matches.
        let leading = pattern.first.map(isWordChar) == true ? "\\b" : ""
        let trailing = pattern.last.map(isWordChar) == true ? "\\b" : ""
        guard let regex = try? NSRegularExpression(
            pattern: "\(leading)\(escaped)\(trailing)",
            options: [.caseInsensitive]
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
