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

            ForEach(headphones.model.equalizerPresets) { option in
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
        // The preset can be changed from another app (e.g. JBL's on a phone) while this one is open.
        .task { headphones.send(headphones.model.equalizerQuery) }
    }
}
