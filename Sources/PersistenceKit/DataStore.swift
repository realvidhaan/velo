import Foundation
import SwiftData

/// Owns the SwiftData container and provides typed helpers over the three
/// models. Single-user, on-device — SwiftData (SQLite under the hood) is the
/// right fit: one persistence stack, no external dependency.
@MainActor
public final class DataStore {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    /// - Parameter inMemory: use an ephemeral store (for tests).
    public init(inMemory: Bool = false) throws {
        let schema = Schema([
            TranscriptionRecord.self,
            DictionaryEntry.self,
            ReplacementRule.self,
            AppProfileRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: History

    public func addRecord(_ record: TranscriptionRecord) {
        context.insert(record)
        try? context.save()
    }

    public func recentRecords(limit: Int = 200, matching query: String = "") -> [TranscriptionRecord] {
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let all = (try? context.fetch(descriptor)) ?? []
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter {
            $0.cleanedText.lowercased().contains(q) || $0.rawText.lowercased().contains(q)
        }
    }

    public func deleteRecord(_ record: TranscriptionRecord) {
        context.delete(record)
        try? context.save()
    }

    public func clearHistory() {
        try? context.delete(model: TranscriptionRecord.self)
        try? context.save()
    }

    // MARK: Dictionary

    public func dictionaryEntries() -> [DictionaryEntry] {
        let descriptor = FetchDescriptor<DictionaryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Terms fed to STT `contextualStrings` and the cleanup prompt.
    public func activeDictionaryTerms() -> [String] {
        dictionaryEntries().filter(\.enabled).map(\.written)
    }

    public func addDictionaryEntry(_ entry: DictionaryEntry) {
        context.insert(entry)
        try? context.save()
    }

    public func deleteDictionaryEntry(_ entry: DictionaryEntry) {
        context.delete(entry)
        try? context.save()
    }

    // MARK: Replacement rules

    public func replacementRules() -> [ReplacementRule] {
        let descriptor = FetchDescriptor<ReplacementRule>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Enabled rules, applied to the raw transcript before cleanup.
    public func activeReplacementRules() -> [ReplacementRule] {
        replacementRules().filter(\.enabled)
    }

    public func addReplacementRule(_ rule: ReplacementRule) {
        context.insert(rule)
        try? context.save()
    }

    public func deleteReplacementRule(_ rule: ReplacementRule) {
        context.delete(rule)
        try? context.save()
    }

    /// One-time migration that closes the "learned but never applied" gap: every
    /// dictionary entry that carries a `spoken` form (i.e. a real substitution)
    /// becomes an active replacement rule, so accepted corrections finally take
    /// effect. Idempotent — skips any (originals, replacement) that already exists.
    public func seedReplacementRulesFromDictionaryIfNeeded() {
        let existing = replacementRules()
        func ruleExists(spoken: String, written: String) -> Bool {
            existing.contains { $0.replacement == written && $0.originals.contains(spoken) }
        }
        var inserted = false
        for entry in dictionaryEntries() {
            guard let spoken = entry.spoken, !spoken.isEmpty,
                  !ruleExists(spoken: spoken, written: entry.written) else { continue }
            context.insert(ReplacementRule(originals: [spoken], replacement: entry.written, isLearned: true))
            inserted = true
        }
        if inserted { try? context.save() }
    }

    // MARK: App profiles

    /// Seeds the built-in profiles the first time the app runs.
    public func seedAppProfilesIfNeeded(_ defaults: [(bundleID: String, displayName: String, hint: String)]) {
        let existing = (try? context.fetch(FetchDescriptor<AppProfileRecord>())) ?? []
        guard existing.isEmpty else { return }
        for d in defaults {
            context.insert(AppProfileRecord(bundleID: d.bundleID, displayName: d.displayName, formattingHint: d.hint))
        }
        try? context.save()
    }

    public func appProfiles() -> [AppProfileRecord] {
        let descriptor = FetchDescriptor<AppProfileRecord>(
            sortBy: [SortDescriptor(\.displayName)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The formatting hint for a bundle ID, or nil if unknown/disabled.
    public func hint(forBundleID bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        let descriptor = FetchDescriptor<AppProfileRecord>(
            predicate: #Predicate { $0.bundleID == bundleID && $0.enabled }
        )
        return (try? context.fetch(descriptor))?.first?.formattingHint
    }

    public func addAppProfile(_ profile: AppProfileRecord) {
        context.insert(profile)
        try? context.save()
    }

    public func deleteAppProfile(_ profile: AppProfileRecord) {
        context.delete(profile)
        try? context.save()
    }

    public func save() {
        try? context.save()
    }
}
