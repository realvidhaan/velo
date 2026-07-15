import SwiftUI
import AppKit
import PersistenceKit

/// Headless PNG rendering of the data-driven settings views, for visual
/// verification without a display. Seeds an in-memory store with sample data.
@MainActor
public enum SettingsSnapshot {
    @discardableResult
    public static func render(to dir: URL) throws -> [URL] {
        let store = try DataStore(inMemory: true)
        store.addDictionaryEntry(DictionaryEntry(written: "Vidhaan", spoken: "vidon"))
        store.addDictionaryEntry(DictionaryEntry(written: "FlowClone"))
        store.addDictionaryEntry(DictionaryEntry(written: "Kubernetes"))
        store.seedAppProfilesIfNeeded([
            ("com.apple.mail", "Mail", "email prose with full punctuation"),
            ("com.apple.MobileSMS", "Messages", "a casual text message; minimal punctuation"),
            ("com.microsoft.VSCode", "VS Code", "verbatim technical dictation"),
        ])
        store.addRecord(TranscriptionRecord(rawText: "um send the report by friday",
                                            cleanedText: "Send the report by Friday.",
                                            sttEngine: "SpeechAnalyzer", llmEngine: "Groq", latencyMS: 720))
        store.addRecord(TranscriptionRecord(rawText: "lets meet at three",
                                            cleanedText: "Let's meet at three.",
                                            sttEngine: "SpeechAnalyzer", llmEngine: "Apple FM", latencyMS: 640))
        store.addReplacementRule(ReplacementRule(originals: ["get hub"], replacement: "GitHub", isLearned: true))

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [URL] = []
        let views: [(String, AnyView)] = [
            ("settings-dictionary", AnyView(DictionarySettingsView(dataStore: store))),
            ("settings-your-voice", AnyView(ReplacementRulesSettingsView(dataStore: store))),
            ("settings-app-profiles", AnyView(AppProfilesSettingsView(dataStore: store))),
            ("settings-history", AnyView(HistorySettingsView(dataStore: store))),
        ]
        for (name, view) in views {
            let framed = view.frame(width: 520, height: 380).background(Color(white: 0.95))
            let renderer = ImageRenderer(content: framed)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = dir.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            written.append(url)
        }
        return written
    }
}
