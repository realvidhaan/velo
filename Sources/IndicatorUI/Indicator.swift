import SwiftUI

/// Visual state of the floating recording pill.
public enum IndicatorState: Equatable, Sendable {
    case hidden
    case recording
    case processing
    case error(String)
}

/// Observable model the SwiftUI indicator view binds to.
@MainActor
public final class IndicatorModel: ObservableObject {
    @Published public var state: IndicatorState = .hidden
    @Published public var level: Float = 0

    public init() {}
}

/// The recording pill: a rounded capsule with live audio bars while recording,
/// a spinner while processing, and a message on error. Kept minimal and
/// unobtrusive, matching Wispr Flow's functional feel without copying its art.
public struct IndicatorView: View {
    @ObservedObject var model: IndicatorModel

    public init(model: IndicatorModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.state {
            case .hidden:
                EmptyView()
            case .recording:
                pill { WaveformBars(level: model.level) }
            case .processing:
                pill {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            case .error(let message):
                pill {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(message).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.state)
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(height: 36)
            .frame(minWidth: 96)
            .background(Capsule().fill(.black.opacity(0.85)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

/// Symmetric audio-level bars driven by the smoothed mic level.
struct WaveformBars: View {
    let level: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: barHeight(for: i))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let distanceFromCenter = abs(Double(index) - Double(barCount - 1) / 2)
        let falloff = 1.0 - distanceFromCenter * 0.22
        return 4.0 + Double(level) * 22.0 * falloff
    }
}
