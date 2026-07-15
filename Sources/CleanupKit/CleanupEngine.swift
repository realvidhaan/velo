import Foundation

/// A demonstrated input→output pair fed to the cleanup LLM as a few-shot
/// example. Superwhisper's docs report 2–3 examples "significantly improve"
/// results; we use them mainly to teach *structure* (lists, email shape).
public struct CleanupExample: Codable, Equatable, Sendable {
    public let input: String
    public let output: String
    public init(input: String, output: String) {
        self.input = input
        self.output = output
    }
}

/// The formatting "personality" for the target app: how the cleaned text should
/// read. Drives the style block of the cleanup prompt.
public struct CleanupStyle: Codable, Equatable, Sendable {
    public enum Tone: String, Codable, Sendable { case formal, casual, verbatim }
    public enum Structure: String, Codable, Sendable { case prose, lists, markdown, email, code }

    public var tone: Tone
    public var structure: Structure
    /// Whether a trailing period is kept (Formal) or dropped (Casual chat).
    public var keepTrailingPunctuation: Bool
    /// Free-text nudge shown to the model (editable per-app by the user).
    public var hint: String

    public init(tone: Tone, structure: Structure, keepTrailingPunctuation: Bool, hint: String) {
        self.tone = tone
        self.structure = structure
        self.keepTrailingPunctuation = keepTrailingPunctuation
        self.hint = hint
    }
}

/// Input to a cleanup pass.
public struct CleanupRequest: Sendable, Equatable {
    /// The raw transcript from STT.
    public var raw: String
    /// Personal-dictionary terms whose spelling should be enforced.
    public var dictionary: [String]
    /// Free-text formatting hint for the focused app (legacy; superseded by
    /// `style` when set, but kept for callers/tests that pass a bare hint).
    public var appHint: String?
    /// The target app's formatting personality (tone + structure).
    public var style: CleanupStyle?
    /// Few-shot demonstrations (structure/style teaching + learned pairs).
    public var examples: [CleanupExample]

    public init(
        raw: String,
        dictionary: [String] = [],
        appHint: String? = nil,
        style: CleanupStyle? = nil,
        examples: [CleanupExample] = []
    ) {
        self.raw = raw
        self.dictionary = dictionary
        self.appHint = appHint
        self.style = style
        self.examples = examples
    }
}

public enum CleanupError: Error, Equatable {
    case unavailable
    case badResponse
    case timedOut
}

/// Cleans up a raw transcript: removes filler words, fixes punctuation and
/// capitalization, applies dictionary spellings and the app formatting hint,
/// without rewriting content. Swappable between cloud (Groq) and local
/// (Apple Foundation Models, Ollama).
public protocol CleanupEngine: Sendable {
    var displayName: String { get }
    /// Whether the engine can run right now (key present, model available…).
    func isAvailable() async -> Bool
    func cleanup(_ request: CleanupRequest) async throws -> String
}
