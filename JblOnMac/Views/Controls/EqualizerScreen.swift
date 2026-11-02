import SwiftUI

/// Equalizer screen, reached from the Equalizer row: one row per predefined preset.
struct EqualizerScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Equalizer") {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            ForEach(EqualizerPreset.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: headphones.state.equalizer == option
                ) {
                    EmptyView()
                } action: {
                    headphones.select(option)
                }
            }
        }
    }
}
