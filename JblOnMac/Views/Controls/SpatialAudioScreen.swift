import SwiftUI

/// Spatial audio screen: one row per mode.
struct SpatialAudioScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Spatial Audio") {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            ForEach(SpatialAudioMode.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: headphones.state.spatialMode == option
                ) {
                    EmptyView()
                } action: {
                    headphones.select(option)
                }
            }
        }
    }
}
