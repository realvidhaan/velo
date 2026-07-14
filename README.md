# FlowClone

An open-source macOS voice-dictation app in the spirit of Wispr Flow: **hold a
global hotkey anywhere, speak, release**, and cleaned-up, formatted text is
inserted at your cursor in whatever app is focused.

- 🎙️ **Hold-to-talk** global hotkey (default: Fn / Globe) that works in any text field system-wide
- ⚡ **Fast**, on-device speech-to-text via Apple's `SpeechAnalyzer` (macOS 26)
- 🧹 **LLM cleanup pass** — removes filler words, fixes punctuation & capitalization
- 🔁 **Swappable engines** — local (SpeechAnalyzer, Apple Foundation Models, Ollama) or free-tier cloud (Groq)
- 📓 Personal dictionary, per-app formatting, and searchable local history

> **Status:** early development. See [milestones](#milestones).

## Requirements

- **macOS 26 (Tahoe) or later** — FlowClone relies on the `SpeechAnalyzer` and
  `FoundationModels` frameworks introduced in macOS 26.
- Xcode 26+ to build.

## Privacy

FlowClone is **not** "fully local" by default. The out-of-the-box configuration
transcribes speech **on-device** with `SpeechAnalyzer`, but sends the resulting
**text** to Groq's free API for the cleanup pass. To keep everything on your
Mac, switch the cleanup engine to **Apple Foundation Models** or **Ollama** in
Settings — then no audio or text leaves your machine.

Audio is held in memory for the duration of an utterance and only written to
disk if you enable history audio retention (off by default).

## Build & run

```sh
make test   # run the unit tests
make run    # build, assemble FlowClone.app, and launch it
```

`make run` produces `build/FlowClone.app`. Because the app is signed ad-hoc (or
with a local development certificate), macOS Gatekeeper may warn on first launch
— right-click the app and choose **Open**, or run
`xattr -dr com.apple.quarantine build/FlowClone.app`.

FlowClone is a menu-bar-only app (no Dock icon). Look for the microphone icon in
your menu bar.

## Architecture

The runtime is a single actor (`DictationController`) driving a strict state
machine over protocol-based services, so both the speech engine and the cleanup
LLM are swappable between local and cloud implementations:

```
CGEventTap (hotkey) → DictationController → AudioCapture → Transcription → Cleanup → TextInjection
```

Logic lives in the `FlowCore` library (unit-tested with `swift test`); the
`FlowCloneApp` executable target holds `@main`, the SwiftUI menu-bar UI, and the
floating recording indicator.

## Setup

On first launch FlowClone shows a setup guide that walks through the three
permissions it needs:

- **Microphone** — to hear you.
- **Input Monitoring** — so the hold-to-talk hotkey works in any app.
- **Accessibility** — so it can insert text into the focused app.

If you use the default **Fn / Globe** hotkey, set that key to **“Do Nothing”**
in System Settings ▸ Keyboard so it doesn't also trigger emoji or system
dictation. You can pick a different hotkey (Right Option, F13) in Settings.

## Milestones

- [x] **M0** — project skeleton, menu-bar app, state machine + tests
- [x] **M1** — global hotkey, audio capture, recording indicator
- [x] **M2** — streaming speech-to-text (`SpeechAnalyzer`)
- [x] **M3** — text injection into the focused app
- [x] **M4** — LLM cleanup pass + per-app formatting
- [x] **M5** — settings, personal dictionary, history
- [x] **M5.5** — correction capture ("learns" your vocabulary)
- [x] **M6** — onboarding & polish
- [ ] **M7** — Command Mode (select text, speak an edit)

## License

[MIT](LICENSE)
