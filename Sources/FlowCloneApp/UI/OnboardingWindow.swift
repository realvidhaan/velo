import SwiftUI
import AppKit
import Combine
import OnboardingUI

/// SwiftUI container that binds the presentational `OnboardingView` to live
/// controller state and polls permissions (which change outside the app, in
/// System Settings) once a second while visible.
struct OnboardingContainerView: View {
    @ObservedObject var controller: AppController
    let onFinish: () -> Void

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        OnboardingView(
            state: controller.onboardingState,
            actions: OnboardingActions(
                grantMicrophone: controller.onboardingGrantMicrophone,
                grantInputMonitoring: controller.onboardingGrantInputMonitoring,
                grantAccessibility: controller.requestAccessibility,
                openKeyboardSettings: controller.openKeyboardSettings,
                finish: {
                    controller.completeOnboarding()
                    onFinish()
                }
            )
        )
        .onReceive(poll) { _ in controller.refreshPermissions() }
    }
}

/// Owns the onboarding `NSWindow`. Menu-bar apps have no default window, so we
/// create one explicitly on first run.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
    }

    func showIfNeeded() {
        guard !controller.hasCompletedOnboarding else { return }
        show()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: OnboardingContainerView(controller: controller) { [weak self] in
                self?.close()
            }
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to FlowClone"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
    }
}
