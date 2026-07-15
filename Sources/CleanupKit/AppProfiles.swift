import Foundation

/// A per-app "personality": the focused app's bundle ID selects a `CleanupStyle`
/// (tone + structure) plus optional few-shot examples, so dictation into Mail
/// reads like an email, Slack like a casual chat, and a code editor stays
/// verbatim. The built-in personalities live here in code; users override the
/// free-text hint per app in Settings (`AppProfileRecord`).
public struct AppProfile: Codable, Equatable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var style: CleanupStyle
    public var examples: [CleanupExample]

    public init(bundleID: String, displayName: String, style: CleanupStyle, examples: [CleanupExample] = []) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.style = style
        self.examples = examples
    }

    /// Back-compat convenience: the plain hint string (seeding, legacy callers).
    public var formattingHint: String { style.hint }
}

/// Built-in personalities, seeded on first launch. Users can edit/add in Settings.
public enum AppProfileDefaults {
    private static func style(_ tone: CleanupStyle.Tone, _ structure: CleanupStyle.Structure,
                              keepPunct: Bool, _ hint: String) -> CleanupStyle {
        CleanupStyle(tone: tone, structure: structure, keepTrailingPunctuation: keepPunct, hint: hint)
    }

    public static let all: [AppProfile] = [
        // Email → greeting/body/sign-off, formal punctuation.
        AppProfile(
            bundleID: "com.apple.mail", displayName: "Mail",
            style: style(.formal, .email, keepPunct: true,
                         "email prose; keep it professional but natural."),
            examples: [
                CleanupExample(
                    input: "hey sarah just wanted to follow up on the proposal can we meet thursday thanks alex",
                    output: "Hi Sarah,\n\nJust wanted to follow up on the proposal — can we meet Thursday?\n\nThanks,\nAlex"
                )
            ]
        ),
        AppProfile(
            bundleID: "com.microsoft.Outlook", displayName: "Outlook",
            style: style(.formal, .email, keepPunct: true, "email prose; professional but natural.")
        ),
        // Chat → casual, no trailing period, lists when enumerating.
        AppProfile(
            bundleID: "com.apple.MobileSMS", displayName: "Messages",
            style: style(.casual, .prose, keepPunct: false,
                         "a casual text message; lowercase is fine, minimal punctuation.")
        ),
        AppProfile(
            bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack",
            style: style(.casual, .lists, keepPunct: false, "a casual work chat message.")
        ),
        AppProfile(
            bundleID: "com.hnc.Discord", displayName: "Discord",
            style: style(.casual, .prose, keepPunct: false, "a casual chat message.")
        ),
        // Notes → structured Markdown.
        AppProfile(
            bundleID: "com.apple.Notes", displayName: "Notes",
            style: style(.formal, .markdown, keepPunct: true, "clear notes; use Markdown structure.")
        ),
        AppProfile(
            bundleID: "notion.id", displayName: "Notion",
            style: style(.formal, .markdown, keepPunct: true, "clear notes; use Markdown structure.")
        ),
        AppProfile(
            bundleID: "md.obsidian", displayName: "Obsidian",
            style: style(.formal, .markdown, keepPunct: true, "Markdown notes.")
        ),
        // Code/terminal → verbatim, no auto-punctuation.
        AppProfile(
            bundleID: "com.microsoft.VSCode", displayName: "VS Code",
            style: style(.verbatim, .code, keepPunct: false,
                         "keep code-like tokens intact; do not add prose punctuation.")
        ),
        AppProfile(
            bundleID: "com.todesktop.230313mzl4w4u92", displayName: "Cursor",
            style: style(.verbatim, .code, keepPunct: false, "keep code-like tokens intact.")
        ),
        AppProfile(
            bundleID: "com.apple.Terminal", displayName: "Terminal",
            style: style(.verbatim, .code, keepPunct: false, "a verbatim shell command; no punctuation.")
        ),
        AppProfile(
            bundleID: "com.googlecode.iterm2", displayName: "iTerm",
            style: style(.verbatim, .code, keepPunct: false, "a verbatim shell command; no punctuation.")
        ),
    ]

    /// The full personality for a bundle ID, or nil if unknown.
    public static func personality(forBundleID bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return all.first { $0.bundleID == bundleID }
    }

    /// The formatting hint for a bundle ID, or nil (neutral) if unknown.
    public static func hint(forBundleID bundleID: String?) -> String? {
        personality(forBundleID: bundleID)?.formattingHint
    }
}
