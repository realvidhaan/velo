import SwiftUI
import PersistenceKit
import LearningKit

/// Personal-dictionary editor. Depends only on `DataStore` so it can be rendered
/// headlessly in tests. State is initialized at construction (not just on
/// appear) so snapshots show data.
public struct DictionarySettingsView: View {
    let dataStore: DataStore
    @State private var entries: [DictionaryEntry]
    @State private var suggestions: [VocabCandidate] = []
    @State private var newWritten = ""
    @State private var newSpoken = ""

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
        _entries = State(initialValue: dataStore.dictionaryEntries())
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("Words and names FlowClone should recognize and spell correctly.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggested from your history")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    ForEach(suggestions, id: \.term) { candidate in
                        HStack {
                            Text(candidate.term).fontWeight(.medium)
                            Text("said \(candidate.count)×").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add") {
                                dataStore.addDictionaryEntry(DictionaryEntry(written: candidate.term))
                                reload()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.horizontal)
            }

            List {
                ForEach(entries, id: \.persistentModelID) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.written).fontWeight(.medium)
                            if let spoken = entry.spoken, !spoken.isEmpty {
                                Text("spoken: \(spoken)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            dataStore.deleteDictionaryEntry(entry); reload()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Written form (e.g. Vidhaan)", text: $newWritten)
                TextField("Spoken (optional)", text: $newSpoken)
                Button("Add") {
                    let written = newWritten.trimmingCharacters(in: .whitespaces)
                    guard !written.isEmpty else { return }
                    let spoken = newSpoken.trimmingCharacters(in: .whitespaces)
                    dataStore.addDictionaryEntry(DictionaryEntry(written: written, spoken: spoken.isEmpty ? nil : spoken))
                    newWritten = ""; newSpoken = ""; reload()
                }
                .disabled(newWritten.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        entries = dataStore.dictionaryEntries()
        // Mine recent history for distinctive words the user says often but
        // hasn't added yet (common words are filtered out).
        let existing = Set(dataStore.dictionaryEntries().map { $0.written.lowercased() })
        let transcripts = dataStore.recentRecords(limit: 200).map(\.rawText)
        suggestions = Array(
            VocabMiner.candidates(from: transcripts, existing: existing).prefix(5)
        )
    }
}

/// Replacement-rules editor — the "Your Voice" transparency panel. Every learned
/// or manual substitution is visible and editable here, so nothing FlowClone
/// learned about you is hidden.
public struct ReplacementRulesSettingsView: View {
    let dataStore: DataStore
    @State private var rules: [ReplacementRule]
    @State private var newFrom = ""
    @State private var newTo = ""

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
        _rules = State(initialValue: dataStore.replacementRules())
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("Heard → written. Applied to every transcript before cleanup. Rules learned from your corrections appear here automatically.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)

            List {
                ForEach(rules, id: \.persistentModelID) { rule in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { rule.enabled = $0; dataStore.save() }
                        )).labelsHidden()
                        VStack(alignment: .leading) {
                            Text(rule.originals.joined(separator: ", ")) + Text("  →  ").foregroundColor(.secondary) + Text(rule.replacement).fontWeight(.medium)
                            if rule.isLearned {
                                Text("learned").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            dataStore.deleteReplacementRule(rule); reload()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Heard (e.g. get hub)", text: $newFrom)
                TextField("Written (e.g. GitHub)", text: $newTo)
                Button("Add") {
                    let from = newFrom.trimmingCharacters(in: .whitespaces)
                    let to = newTo.trimmingCharacters(in: .whitespaces)
                    guard !from.isEmpty, !to.isEmpty else { return }
                    dataStore.addReplacementRule(ReplacementRule(originals: [from], replacement: to))
                    newFrom = ""; newTo = ""; reload()
                }
                .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty
                          || newTo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .onAppear(perform: reload)
    }

    private func reload() { rules = dataStore.replacementRules() }
}

/// Per-app formatting-hint editor.
public struct AppProfilesSettingsView: View {
    let dataStore: DataStore
    @State private var profiles: [AppProfileRecord]

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
        _profiles = State(initialValue: dataStore.appProfiles())
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("How dictation is formatted per app (email vs casual text vs code).")
                .font(.caption).foregroundStyle(.secondary)
                .padding([.horizontal, .top])

            List {
                ForEach(profiles, id: \.persistentModelID) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { profile.enabled },
                                set: { profile.enabled = $0; dataStore.save() }
                            )).labelsHidden()
                            Text(profile.displayName).fontWeight(.medium)
                            Spacer()
                            Text(profile.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("Formatting hint", text: Binding(
                            get: { profile.formattingHint },
                            set: { profile.formattingHint = $0; dataStore.save() }
                        ), axis: .vertical)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// Searchable dictation history.
public struct HistorySettingsView: View {
    let dataStore: DataStore
    @State private var records: [TranscriptionRecord]
    @State private var query = ""

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
        _records = State(initialValue: dataStore.recentRecords())
    }

    public var body: some View {
        VStack {
            HStack {
                TextField("Search history", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, _ in reload() }
                Button("Clear all", role: .destructive) { dataStore.clearHistory(); reload() }
            }
            .padding([.horizontal, .top])

            List {
                ForEach(records, id: \.persistentModelID) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.cleanedText)
                        HStack(spacing: 8) {
                            Text(record.date, style: .time)
                            Text(record.llmEngine)
                            Text("\(record.latencyMS)ms")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.cleanedText, forType: .string)
                        }
                        Button("Delete", role: .destructive) { dataStore.deleteRecord(record); reload() }
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { records = dataStore.recentRecords(matching: query) }
}
