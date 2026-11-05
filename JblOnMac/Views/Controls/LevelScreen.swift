import SwiftUI

/// Second screen with the strength slider (1...7) for one mode, reached from the row's chevron.
struct LevelScreen: View {
    let headphones: HeadphoneController
    let mode: ListeningMode
    @Binding var screen: Screen
    /// The thumb position while dragging. It moves freely and snaps to a step on release, while the
    /// stored state and the writes use the rounded step.
    @State private var dragValue: Double?

    /// The strength level (1...7) closest to a slider position.
    static func level(for position: Double) -> Int {
        Int(position.rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: mode.title) {
                screen = .ambientSound
            } trailing: {
                // The current strength, top right, like the Balance screen.
                if let level = headphones.state.level(for: mode) {
                    Text("Level \(level)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            slider
        }
    }

    private var slider: some View {
        let binding = Binding<Double>(
            get: {
                dragValue ?? Double((mode == .noiseCanceling ? headphones.state.noiseCancelingLevel
                        : headphones.state.ambientAwareLevel) ?? 4)
            },
            set: {
                dragValue = $0
                headphones.setLevel(Self.level(for: $0), for: mode)
            }
        )
        return HStack(spacing: 8) {
            Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
            Slider(value: binding, in: 1 ... 7) { editing in
                if !editing {
                    dragValue = nil
                }
            }
            Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityLabel(String(localized: "\(String(localized: mode.title)) level"))
    }
}
