import SwiftUI

/// Smart audio and video screen: one row per mode.
struct SmartAudioScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Smart Audio & Video") {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            ForEach(SmartAudioMode.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: headphones.state.smartMode == option
                ) {
                    EmptyView()
                } action: {
                    headphones.select(option)
                }
            }
        }
    }
}
