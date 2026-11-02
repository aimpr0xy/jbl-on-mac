import SwiftUI

/// Second screen with the strength slider (1...7) for one mode, reached from the row's chevron.
struct LevelScreen: View {
    let headphones: HeadphoneController
    let mode: ListeningMode
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: mode.rawValue) {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            slider
        }
    }

    private var slider: some View {
        let binding = Binding<Double>(
            get: {
                Double((mode == .noiseCanceling ? headphones.noiseCancelingLevel
                                                : headphones.ambientAwareLevel) ?? 4)
            },
            set: { headphones.setLevel(Int($0), for: mode) }
        )
        return HStack(spacing: 8) {
            Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
            Slider(value: binding, in: 1...7, step: 1)
            Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityLabel("\(mode.rawValue) level")
    }
}
