import XCTest
@testable import PersistenceKit

@MainActor
final class DataStoreTests: XCTestCase {
    private func makeStore() throws -> DataStore {
        try DataStore(inMemory: true)
    }

    func testDictionaryAddFetchDelete() throws {
        let store = try makeStore()
        store.addDictionaryEntry(DictionaryEntry(written: "Vidhaan"))
        store.addDictionaryEntry(DictionaryEntry(written: "Velo", spoken: "flow clone"))
        XCTAssertEqual(store.dictionaryEntries().count, 2)
        XCTAssertEqual(Set(store.activeDictionaryTerms()), ["Vidhaan", "Velo"])

        let first = store.dictionaryEntries().first!
        store.deleteDictionaryEntry(first)
        XCTAssertEqual(store.dictionaryEntries().count, 1)
    }

    func testDisabledTermsExcludedFromActive() throws {
        let store = try makeStore()
        let entry = DictionaryEntry(written: "Xyzzy", enabled: false)
        store.addDictionaryEntry(entry)
        XCTAssertFalse(store.activeDictionaryTerms().contains("Xyzzy"))
    }

    func testReplacementRuleCRUD() throws {
        let store = try makeStore()
        store.addReplacementRule(ReplacementRule(originals: ["get hub"], replacement: "GitHub"))
        store.addReplacementRule(ReplacementRule(originals: ["voicing"], replacement: "VoiceInk", enabled: false))
        XCTAssertEqual(store.replacementRules().count, 2)
        XCTAssertEqual(store.activeReplacementRules().map(\.replacement), ["GitHub"])

        store.deleteReplacementRule(store.replacementRules().first!)
        XCTAssertEqual(store.replacementRules().count, 1)
    }

    func testSeedReplacementRulesFromDictionaryMigration() throws {
        let store = try makeStore()
        // A learned substitution (has `spoken`) and a plain spelling term (no spoken).
        store.addDictionaryEntry(DictionaryEntry(written: "Vidhaan", spoken: "vidon"))
        store.addDictionaryEntry(DictionaryEntry(written: "Swift"))

        store.seedReplacementRulesFromDictionaryIfNeeded()
        let rules = store.replacementRules()
        XCTAssertEqual(rules.count, 1, "only the entry with a spoken form becomes a rule")
        XCTAssertEqual(rules.first?.replacement, "Vidhaan")
        XCTAssertEqual(rules.first?.originals, ["vidon"])
        XCTAssertTrue(rules.first?.isLearned ?? false)

        // Idempotent: running again doesn't duplicate.
        store.seedReplacementRulesFromDictionaryIfNeeded()
        XCTAssertEqual(store.replacementRules().count, 1)
    }

    func testHistoryAddSearchClear() throws {
        let store = try makeStore()
        store.addRecord(TranscriptionRecord(rawText: "hello world", cleanedText: "Hello world.",
                                            sttEngine: "SA", llmEngine: "Groq", latencyMS: 500))
        store.addRecord(TranscriptionRecord(rawText: "buy milk", cleanedText: "Buy milk.",
                                            sttEngine: "SA", llmEngine: "Groq", latencyMS: 400))
        XCTAssertEqual(store.recentRecords().count, 2)
        XCTAssertEqual(store.recentRecords(matching: "milk").count, 1)
        XCTAssertEqual(store.recentRecords(matching: "hello").first?.cleanedText, "Hello world.")

        store.clearHistory()
        XCTAssertEqual(store.recentRecords().count, 0)
    }

    func testHistorySortedNewestFirst() throws {
        let store = try makeStore()
        let old = TranscriptionRecord(date: Date(timeIntervalSince1970: 1000), rawText: "old", cleanedText: "Old.",
                                      sttEngine: "SA", llmEngine: "L", latencyMS: 1)
        let new = TranscriptionRecord(date: Date(timeIntervalSince1970: 2000), rawText: "new", cleanedText: "New.",
                                      sttEngine: "SA", llmEngine: "L", latencyMS: 1)
        store.addRecord(old); store.addRecord(new)
        XCTAssertEqual(store.recentRecords().first?.cleanedText, "New.")
    }

    func testAppProfileSeedAndHint() throws {
        let store = try makeStore()
        store.seedAppProfilesIfNeeded([
            ("com.apple.mail", "Mail", "email prose"),
            ("com.apple.MobileSMS", "Messages", "casual text"),
        ])
        XCTAssertEqual(store.appProfiles().count, 2)
        XCTAssertEqual(store.hint(forBundleID: "com.apple.mail"), "email prose")
        XCTAssertNil(store.hint(forBundleID: "com.unknown.app"))

        // Seeding again is a no-op (doesn't duplicate).
        store.seedAppProfilesIfNeeded([("com.new.app", "New", "x")])
        XCTAssertEqual(store.appProfiles().count, 2)
    }

    func testDisabledProfileHintIgnored() throws {
        let store = try makeStore()
        store.seedAppProfilesIfNeeded([("com.apple.mail", "Mail", "email prose")])
        let profile = store.appProfiles().first!
        profile.enabled = false
        store.save()
        XCTAssertNil(store.hint(forBundleID: "com.apple.mail"))
    }
}
