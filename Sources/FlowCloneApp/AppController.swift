import Foundation
import SwiftUI
import os
import FlowCore
import HotkeyService
import AudioService
import IndicatorUI
import TranscriptionKit
import InjectionKit
import CleanupKit
import PersistenceKit
import LearningKit
import OnboardingUI
import CommandModeKit

/// Top-level runtime coordinator. Owns the hotkey, audio, and indicator, and
/// drives the shared `DictationStateMachine`. In M1 the pipeline ends after
/// recording (transcription/cleanup/injection arrive in later milestones), but
/// the wiring is already shaped so those slot in.
@MainActor
final class AppController: ObservableObject {
    private let log = Logger(subsystem: "com.flowclone.app", category: "AppController")

    private let hotkeys: HotkeyService
    private let commandHotkeys: HotkeyService
    private let audio = AudioCaptureService()
    let indicator = IndicatorController()

    private let sttEngine: any TranscriptionEngine = SpeechAnalyzerEngine()
    private var session: (any TranscriptionSession)?
    private let injector: any TextInjector = PasteInjector()

    let dataStore: DataStore
    let settings: SettingsStore

    /// Bundle ID of the app focused when recording started — used for the
    /// per-app formatting hint and history.
    private var targetBundleID: String?
    /// Timestamp when the user released the key (for latency measurement).
    private var releaseTime: Date?
    /// Which flavor of session is currently running.
    private var currentMode: SessionMode = .dictation
    /// The selected text captured when Command Mode started.
    private var commandSelection: String?

    // Correction capture ("learning").
    private let corrections = CorrectionObserver(store: UserDefaultsCorrectionCountStore())
    /// Snapshot of the focused field just after our last injection, used to
    /// detect the user's edits before the next dictation.
    private var postInjectionSnapshot: (text: String, bundleID: String?)?
    /// A substitution that recurred enough to suggest adding to the dictionary.
    @Published private(set) var pendingSuggestion: Substitution?

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var hotkeyActive = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var microphoneGranted = false
    @Published private(set) var speechModelInstalled = false
    @Published private(set) var lastLevel: Float = 0
    /// The most recent transcript, surfaced in the menu (visible proof STT works
    /// before injection lands in M3).
    @Published private(set) var lastTranscript: String = ""

    /// Minimum hold before we actually commit to a recording session, so a
    /// quick accidental tap of the hotkey doesn't flash the pill.
    private let holdDebounce: Duration = .milliseconds(150)
    private var armTask: Task<Void, Never>?

    init(dataStore: DataStore, settings: SettingsStore) {
        self.dataStore = dataStore
        self.settings = settings
        self.hotkeys = HotkeyService(hotkey: settings.hotkey)
        self.commandHotkeys = HotkeyService(hotkey: settings.commandHotkey)
        audio.onLevel = { [weak self] level in
            self?.lastLevel = level
            self?.indicator.update(level: level)
        }
        hotkeys.onEvent = { [weak self] event in
            self?.handle(hotkey: event, mode: .dictation)
        }
        commandHotkeys.onEvent = { [weak self] event in
            self?.handle(hotkey: event, mode: .command)
        }
        // Seed the built-in app profiles on first run.
        dataStore.seedAppProfilesIfNeeded(
            AppProfileDefaults.all.map { ($0.bundleID, $0.displayName, $0.formattingHint) }
        )
    }

    /// Re-applies the configured hotkeys (called when the user changes them).
    func applyHotkeySetting() {
        hotkeys.update(hotkey: settings.hotkey)
        commandHotkeys.update(hotkey: settings.commandHotkey)
    }

    /// Starts or stops the command-mode tap when the user toggles the feature.
    func applyCommandModeSetting() {
        if settings.commandModeEnabled {
            commandHotkeys.update(hotkey: settings.commandHotkey)
            commandHotkeys.start()
        } else {
            commandHotkeys.stop()
        }
    }

    // MARK: Startup

    /// Requests permissions and starts the hotkey tap. Safe to call repeatedly
    /// (e.g. after the user grants a permission in System Settings).
    func startServices() {
        Task { self.microphoneGranted = await AudioCaptureService.requestMicrophone() }
        // Pre-install the speech model so the first dictation isn't slow.
        Task {
            try? await sttEngine.prepare()
            self.speechModelInstalled = true
        }

        if HotkeyService.inputMonitoringStatus != .granted {
            HotkeyService.requestInputMonitoring()
        }
        hotkeyActive = hotkeys.start()
        if settings.commandModeEnabled { commandHotkeys.start() }
        if !hotkeyActive {
            log.notice("Hotkey inactive — Input Monitoring not granted yet")
        }
        accessibilityGranted = Accessibility.isTrusted
        microphoneGranted = AudioCaptureService.microphoneAuthorized
    }

    func retryHotkey() {
        guard !hotkeyActive else { return }
        hotkeyActive = hotkeys.start()
        accessibilityGranted = Accessibility.isTrusted
    }

    func requestAccessibility() {
        Accessibility.requestIfNeeded()
        accessibilityGranted = Accessibility.isTrusted
    }

    // MARK: Onboarding

    /// Refreshes all permission-related state (polled while onboarding is open).
    func refreshPermissions() {
        microphoneGranted = AudioCaptureService.microphoneAuthorized
        accessibilityGranted = Accessibility.isTrusted
        if !hotkeyActive { hotkeyActive = hotkeys.start() }
    }

    /// Whether the Globe/Fn key is set to "Do Nothing" (only relevant when the
    /// hotkey is Fn; otherwise there's nothing to neutralize).
    private var globeKeyNeutralized: Bool {
        guard settings.hotkeyModifier == .fn else { return true }
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int
        return (value ?? 0) == 0
    }

    var onboardingState: OnboardingState {
        OnboardingState(
            microphoneGranted: microphoneGranted,
            inputMonitoringGranted: hotkeyActive,
            accessibilityGranted: accessibilityGranted,
            globeKeyNeutralized: globeKeyNeutralized,
            speechModelInstalled: speechModelInstalled
        )
    }

    func onboardingGrantMicrophone() {
        Task { self.microphoneGranted = await AudioCaptureService.requestMicrophone() }
    }

    func onboardingGrantInputMonitoring() {
        HotkeyService.requestInputMonitoring()
        retryHotkey()
    }

    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    var hasCompletedOnboarding: Bool { settings.hasCompletedOnboarding }
    func completeOnboarding() { settings.hasCompletedOnboarding = true }

    // MARK: Hotkey handling

    private func handle(hotkey event: HotkeyEvent, mode: SessionMode) {
        switch event {
        case .down:
            beginSession(mode)
        case .up:
            endRecording(mode: mode)
        case .cancel:
            cancel(mode: mode)
        }
    }

    private func beginSession(_ mode: SessionMode) {
        // `armTask == nil` also blocks a second press during the debounce window,
        // when `state` is still `.idle` but a session is already arming.
        guard case .idle = state, armTask == nil else { return }
        currentMode = mode
        // Capture the target app now (FlowClone is a menu-bar agent and never
        // becomes frontmost, so this stays the user's app through the session).
        targetBundleID = FocusedAppInspector.frontmostBundleID

        if mode == .command {
            // Command Mode needs a selection to edit.
            guard let selection = SelectionReader.read(), !selection.isEmpty else {
                showTransientError("Select text first")
                return
            }
            commandSelection = selection
        } else {
            // Before dictation, check whether the user edited our last injection.
            detectCorrectionIfEnabled()
        }

        // Start capturing immediately (cheap), but only reveal the pill and
        // commit to the session after the debounce, so taps don't flicker.
        startAudio()
        armTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.holdDebounce)
            guard !Task.isCancelled else { return }
            self.transition(.hotkeyDown(mode))
            self.indicator.show(.recording)
            await self.startSession()
            self.armTask = nil
        }
    }

    private func startSession() async {
        do {
            let terms = dataStore.activeDictionaryTerms()
            let session = try await sttEngine.makeSession(contextualStrings: terms)
            // Only attach if we're still recording (user may have released).
            guard case .recording = state else {
                await session.cancel()
                return
            }
            self.session = session
            audio.onBuffer = { [weak session] buffer in
                session?.feed(buffer)
            }
        } catch {
            log.error("Failed to start STT session: \(error.localizedDescription, privacy: .public)")
            indicator.setState(.error("Speech model unavailable"))
            transition(.failed("Speech model unavailable"))
            scheduleErrorReset()
        }
    }

    private func endRecording(mode: SessionMode) {
        // Only the hotkey that started the session can end it, so tapping the
        // command hotkey doesn't terminate an active dictation (and vice-versa).
        guard mode == currentMode else { return }
        armTask?.cancel()
        armTask = nil
        audio.onBuffer = nil
        stopAudio()

        switch state {
        case .recording:
            releaseTime = Date()
            transition(.hotkeyUp)          // -> transcribing
            indicator.setState(.processing)
            Task { [weak self] in await self?.finishTranscription() }
        default:
            // Debounce hadn't fired, or an error is showing: nothing to finalize.
            if state.isBusy { transition(.cancel) }
            discardSession()
            indicator.hide()
        }
    }

    private func finishTranscription() async {
        guard let session else {
            state = .idle
            indicator.hide()
            return
        }
        self.session = nil
        do {
            let transcript = try await session.finish()
            log.info("Transcript: \(transcript, privacy: .public)")
            transition(.transcriptFinalized(transcript))
            // If the user cancelled while we were finalizing (or the transcript
            // was empty), the machine is back to idle — stop here, don't inject.
            guard case .cleaning = state else {
                indicator.hide()
                return
            }

            if currentMode == .command {
                await runCommandEdit(instruction: transcript)
                return
            }

            // cleaning: run the LLM cleanup pass (or fast/deterministic path).
            let hint = dataStore.hint(forBundleID: targetBundleID)
                ?? AppProfileDefaults.hint(forBundleID: targetBundleID)
            let terms = dataStore.activeDictionaryTerms()
            let request = CleanupRequest(raw: transcript, dictionary: terms, appHint: hint)
            let (cleaned, llmName) = await runCleanup(request)
            transition(.cleaned(cleaned))       // cleaning -> injecting
            // Bail if cancelled during the (possibly slow) cleanup pass.
            guard case .injecting = state else { return }
            lastTranscript = cleaned
            inject(cleaned)
            recordHistory(raw: transcript, cleaned: cleaned, llmEngine: llmName)
        } catch {
            log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            indicator.setState(.error("Transcription failed"))
            transition(.failed("Transcription failed"))
            scheduleErrorReset()
        }
    }

    /// Runs cleanup and reports which engine layer produced the text (best
    /// effort, for history). Engine selection follows the user's setting.
    private func runCleanup(_ request: CleanupRequest) async -> (String, String) {
        let engines = cleanupEngines()
        let name = engines.first?.displayName ?? "Local polish"
        let cleaned = await CleanupPipeline(engines: engines).cleanup(request)
        return (cleaned, name)
    }

    /// Builds the cleanup chain from the user's engine choice.
    /// - `.auto`: Groq if a key is set (with Apple FM offline fallback), else local polish.
    private func cleanupEngines() -> [any CleanupEngine] {
        let key = KeychainStore.get(.groqAPIKey)
        let hasKey = (key?.isEmpty == false)
        switch settings.cleanupChoice {
        case .auto:
            guard hasKey else { return [] }
            return [GroqCleanupEngine(apiKey: key, model: settings.groqModel), FoundationModelCleanupEngine()]
        case .groq:
            guard hasKey else { return [] }
            return [GroqCleanupEngine(apiKey: key, model: settings.groqModel)]
        case .appleFoundation:
            return [FoundationModelCleanupEngine()]
        case .ollama:
            return [OllamaCleanupEngine(model: settings.ollamaModel)]
        case .localOnly:
            return []
        }
    }

    // MARK: Command Mode

    /// Applies the spoken instruction to the captured selection and replaces it.
    private func runCommandEdit(instruction: String) async {
        guard let selection = commandSelection else {
            state = .idle
            indicator.hide()
            return
        }
        commandSelection = nil
        do {
            let edited = try await commandRunner().run(
                CommandRequest(selection: selection, instruction: instruction)
            )
            transition(.cleaned(edited))    // -> injecting
            // Bail if the user cancelled while the edit was running.
            guard case .injecting = state else { return }
            lastTranscript = edited
            // The selection is still highlighted, so paste replaces it.
            inject(edited)
        } catch {
            log.error("Command edit failed: \(error.localizedDescription, privacy: .public)")
            indicator.setState(.error("Couldn't edit selection"))
            transition(.failed("Command failed"))
            scheduleErrorReset()
        }
    }

    private func commandRunner() -> CommandRunner {
        var editors: [any CommandEditor] = []
        if let key = KeychainStore.get(.groqAPIKey), !key.isEmpty {
            editors.append(GroqCommandEditor(apiKey: key, model: settings.groqModel))
        }
        editors.append(FoundationModelCommandEditor())
        return CommandRunner(editors: editors)
    }

    /// Shows an error on the pill for ~1.5s without touching the state machine
    /// (used for pre-session failures like "no selection").
    private func showTransientError(_ message: String) {
        indicator.show(.error(message))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            self?.indicator.hide()
        }
    }

    private func recordHistory(raw: String, cleaned: String, llmEngine: String) {
        let latency = releaseTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        dataStore.addRecord(TranscriptionRecord(
            rawText: raw,
            cleanedText: cleaned,
            sttEngine: sttEngine.displayName,
            llmEngine: llmEngine,
            latencyMS: latency,
            targetBundleID: targetBundleID
        ))
    }

    // MARK: Correction capture

    /// If enabled, diff the focused field against our last injection to detect a
    /// user correction, and surface a dictionary suggestion if one recurs.
    private func detectCorrectionIfEnabled() {
        guard settings.learnFromCorrections,
              let snapshot = postInjectionSnapshot,
              snapshot.bundleID == FocusedAppInspector.frontmostBundleID,
              let current = FocusedFieldReader.focusedText(),
              current != snapshot.text else { return }
        postInjectionSnapshot = nil
        let suggestions = corrections.record(injected: snapshot.text, corrected: current)
        if let first = suggestions.first {
            pendingSuggestion = first
        }
    }

    private func captureCorrectionBaseline() {
        guard settings.learnFromCorrections else { return }
        let bundleID = targetBundleID
        // Read after a beat so the paste has landed in the field.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            if let text = FocusedFieldReader.focusedText() {
                self.postInjectionSnapshot = (text, bundleID)
            }
        }
    }

    func acceptSuggestion() {
        guard let suggestion = pendingSuggestion else { return }
        dataStore.addDictionaryEntry(DictionaryEntry(written: suggestion.to, spoken: suggestion.from))
        corrections.clear(suggestion)
        pendingSuggestion = nil
    }

    func dismissSuggestion() {
        if let suggestion = pendingSuggestion { corrections.clear(suggestion) }
        pendingSuggestion = nil
    }

    private func inject(_ text: String) {
        do {
            try injector.inject(text)
            transition(.injected)          // -> idle
            indicator.hide()
            captureCorrectionBaseline()
        } catch InjectionError.secureInputActive {
            log.notice("Secure input active; text left on clipboard")
            indicator.setState(.error("Secure field — copied instead"))
            transition(.failed("Secure field — copied instead"))
            scheduleErrorReset()
        } catch InjectionError.accessibilityNotGranted {
            log.notice("Accessibility not granted; cannot inject")
            indicator.setState(.error("Grant Accessibility to insert text"))
            transition(.failed("Grant Accessibility"))
            scheduleErrorReset()
        } catch {
            log.error("Injection failed: \(error.localizedDescription, privacy: .public)")
            indicator.setState(.error("Couldn't insert text"))
            transition(.failed("Injection failed"))
            scheduleErrorReset()
        }
    }

    private func cancel(mode: SessionMode) {
        // Esc is emitted on both taps; only the one matching the active session
        // acts (the other is a no-op).
        guard mode == currentMode else { return }
        armTask?.cancel()
        armTask = nil
        audio.onBuffer = nil
        stopAudio()
        if state.isBusy { transition(.cancel) }
        discardSession()
        indicator.hide()
    }

    private func discardSession() {
        guard let session else { return }
        self.session = nil
        Task { await session.cancel() }
    }

    private func scheduleErrorReset() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if case .error = self.state {
                self.transition(.reset)
                self.indicator.hide()
            }
        }
    }

    // MARK: Audio

    private func startAudio() {
        do { try audio.start() } catch {
            log.error("Audio start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopAudio() {
        audio.stop()
    }

    // MARK: State machine

    private func transition(_ event: DictationEvent) {
        state = DictationStateMachine.reduce(state, event)
    }
}
