import SwiftUI
import AppKit

/// Headless PNG rendering of the onboarding screen in a couple of states.
@MainActor
public enum OnboardingSnapshot {
    @discardableResult
    public static func render(to dir: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases: [(String, OnboardingState)] = [
            ("onboarding-fresh", OnboardingState()),
            ("onboarding-partial", OnboardingState(
                microphoneGranted: true, inputMonitoringGranted: true,
                accessibilityGranted: false, globeKeyNeutralized: true,
                speechModelInstalled: true)),
            ("onboarding-complete", OnboardingState(
                microphoneGranted: true, inputMonitoringGranted: true,
                accessibilityGranted: true, globeKeyNeutralized: true,
                speechModelInstalled: true)),
        ]
        var written: [URL] = []
        for (name, state) in cases {
            let view = OnboardingView(state: state).background(Color(white: 0.97))
            let renderer = ImageRenderer(content: view)
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
