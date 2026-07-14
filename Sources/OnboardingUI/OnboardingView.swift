import SwiftUI

/// Live permission/setup state driving the onboarding checklist. Kept as a plain
/// value so the view renders headlessly in tests.
public struct OnboardingState: Equatable, Sendable {
    public var microphoneGranted: Bool
    public var inputMonitoringGranted: Bool
    public var accessibilityGranted: Bool
    public var globeKeyNeutralized: Bool
    public var speechModelInstalled: Bool

    public init(
        microphoneGranted: Bool = false,
        inputMonitoringGranted: Bool = false,
        accessibilityGranted: Bool = false,
        globeKeyNeutralized: Bool = false,
        speechModelInstalled: Bool = false
    ) {
        self.microphoneGranted = microphoneGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.accessibilityGranted = accessibilityGranted
        self.globeKeyNeutralized = globeKeyNeutralized
        self.speechModelInstalled = speechModelInstalled
    }

    public var isComplete: Bool {
        microphoneGranted && inputMonitoringGranted && accessibilityGranted
    }
}

/// Actions the onboarding rows can trigger. Defaulted to no-ops for previews/tests.
public struct OnboardingActions {
    public var grantMicrophone: () -> Void
    public var grantInputMonitoring: () -> Void
    public var grantAccessibility: () -> Void
    public var openKeyboardSettings: () -> Void
    public var finish: () -> Void

    public init(
        grantMicrophone: @escaping () -> Void = {},
        grantInputMonitoring: @escaping () -> Void = {},
        grantAccessibility: @escaping () -> Void = {},
        openKeyboardSettings: @escaping () -> Void = {},
        finish: @escaping () -> Void = {}
    ) {
        self.grantMicrophone = grantMicrophone
        self.grantInputMonitoring = grantInputMonitoring
        self.grantAccessibility = grantAccessibility
        self.openKeyboardSettings = openKeyboardSettings
        self.finish = finish
    }
}

/// First-run walkthrough: grant the three permissions, neutralize the Globe key,
/// and confirm the speech model is installed.
public struct OnboardingView: View {
    let state: OnboardingState
    let actions: OnboardingActions

    public init(state: OnboardingState, actions: OnboardingActions = OnboardingActions()) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to FlowClone")
                    .font(.largeTitle).fontWeight(.semibold)
                Text("Hold a key anywhere, speak, release — your words appear as text.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                row(
                    title: "Microphone",
                    detail: "So FlowClone can hear you.",
                    done: state.microphoneGranted,
                    action: ("Allow", actions.grantMicrophone)
                )
                row(
                    title: "Input Monitoring",
                    detail: "So the hold-to-talk hotkey works everywhere.",
                    done: state.inputMonitoringGranted,
                    action: ("Grant", actions.grantInputMonitoring)
                )
                row(
                    title: "Accessibility",
                    detail: "So FlowClone can insert text into the focused app.",
                    done: state.accessibilityGranted,
                    action: ("Grant", actions.grantAccessibility)
                )
                row(
                    title: "Globe / Fn key",
                    detail: "Set it to “Do Nothing” so it doesn't trigger emoji or dictation.",
                    done: state.globeKeyNeutralized,
                    action: ("Open Keyboard Settings", actions.openKeyboardSettings)
                )
                row(
                    title: "Speech model",
                    detail: state.speechModelInstalled ? "Installed." : "Downloading on first use…",
                    done: state.speechModelInstalled,
                    action: nil
                )
            }

            HStack {
                Spacer()
                Button(state.isComplete ? "Start dictating" : "Continue") {
                    actions.finish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.isComplete)
            }
        }
        .padding(28)
        .frame(width: 480)
    }

    private func row(title: String, detail: String, done: Bool, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done, let (label, handler) = action {
                Button(label, action: handler)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
    }
}
