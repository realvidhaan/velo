import SwiftUI
import AppKit

/// Headless rendering of the indicator states to PNG files via `ImageRenderer`.
/// Lets us visually verify the UI with no display or Screen Recording
/// permission — driven from a unit test.
@MainActor
public enum IndicatorSnapshot {
    public struct Case: Sendable {
        public let name: String
        public let state: IndicatorState
        public let level: Float
    }

    public static let allCases: [Case] = [
        Case(name: "indicator-recording-low", state: .recording, level: 0.25),
        Case(name: "indicator-recording-high", state: .recording, level: 0.95),
        Case(name: "indicator-processing", state: .processing, level: 0),
        Case(name: "indicator-error", state: .error("No text field"), level: 0),
    ]

    /// Renders every case to `<dir>/<name>.png`. Returns the written file URLs.
    @discardableResult
    public static func render(to dir: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [URL] = []
        for c in allCases {
            let model = IndicatorModel()
            model.state = c.state
            model.level = c.level
            let view = ZStack {
                Color(white: 0.4)
                IndicatorView(model: model)
            }
            .frame(width: 220, height: 72)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                continue
            }
            let url = dir.appendingPathComponent("\(c.name).png")
            try? png.write(to: url)
            written.append(url)
        }
        return written
    }
}
