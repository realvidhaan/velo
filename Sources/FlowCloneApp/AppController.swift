import Foundation
import SwiftUI
import os
import FlowCore
import HotkeyService
import AudioService
import IndicatorUI

/// Top-level runtime coordinator. Owns the hotkey, audio, and indicator, and
/// drives the shared `DictationStateMachine`. In M1 the pipeline ends after
/// recording (transcription/cleanup/injection arrive in later milestones), but
/// the wiring is already shaped so those slot in.
@MainActor
final class AppController: ObservableObject {
    private let log = Logger(subsystem: "com.flowclone.app", category: "AppController")

    private let hotkeys = HotkeyService(hotkey: .fn)
    private let audio = AudioCaptureService()
    let indicator = IndicatorController()

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var hotkeyActive = false
    @Published private(set) var lastLevel: Float = 0

    /// Minimum hold before we actually commit to a recording session, so a
    /// quick accidental tap of the hotkey doesn't flash the pill.
    private let holdDebounce: Duration = .milliseconds(150)
    private var armTask: Task<Void, Never>?

    init() {
        audio.onLevel = { [weak self] level in
            self?.lastLevel = level
            self?.indicator.update(level: level)
        }
        hotkeys.onEvent = { [weak self] event in
            self?.handle(hotkey: event)
        }
    }

    // MARK: Startup

    /// Requests permissions and starts the hotkey tap. Safe to call repeatedly
    /// (e.g. after the user grants a permission in System Settings).
    func startServices() {
        Task { _ = await AudioCaptureService.requestMicrophone() }

        if HotkeyService.inputMonitoringStatus != .granted {
            HotkeyService.requestInputMonitoring()
        }
        hotkeyActive = hotkeys.start()
        if !hotkeyActive {
            log.notice("Hotkey inactive — Input Monitoring not granted yet")
        }
    }

    func retryHotkey() {
        guard !hotkeyActive else { return }
        hotkeyActive = hotkeys.start()
    }

    // MARK: Hotkey handling

    private func handle(hotkey event: HotkeyEvent) {
        switch event {
        case .down:
            beginArming()
        case .up:
            endRecording()
        case .cancel:
            cancel()
        }
    }

    private func beginArming() {
        guard case .idle = state else { return }
        // Start capturing immediately (cheap), but only reveal the pill and
        // commit to the session after the debounce, so taps don't flicker.
        startAudio()
        armTask?.cancel()
        armTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.holdDebounce)
            guard !Task.isCancelled else { return }
            self.transition(.hotkeyDown(.dictation))
            self.indicator.show(.recording)
        }
    }

    private func endRecording() {
        armTask?.cancel()
        armTask = nil
        stopAudio()

        switch state {
        case .recording:
            // M1: no transcription yet — log and return to idle.
            transition(.hotkeyUp)
            log.info("Recording finished (transcription lands in M2)")
            // Short 'processing' flash, then hide, to preview the real flow.
            indicator.setState(.processing)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.finishToIdle()
            }
        default:
            // Debounce hadn't fired: nothing to show.
            indicator.hide()
            if state.isBusy { transition(.cancel) }
        }
    }

    private func cancel() {
        armTask?.cancel()
        armTask = nil
        stopAudio()
        if state.isBusy { transition(.cancel) }
        indicator.hide()
    }

    private func finishToIdle() {
        if case .transcribing = state { transition(.transcriptFinalized("")) }
        state = .idle
        indicator.hide()
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
