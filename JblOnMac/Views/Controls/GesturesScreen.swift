import SwiftUI

/// Touch controls screen of one earbud: one row per option.
struct GesturesScreen: View {
    let headphones: HeadphoneController
    let side: EarbudSide
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: side.touchControlsTitle) {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            ForEach(GestureControl.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: headphones.state.gestureControl(for: side) == option
                ) {
                    EmptyView()
                } action: {
                    headphones.select(option, for: side)
                }
            }
        }
    }
}
