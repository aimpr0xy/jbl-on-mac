import SwiftUI

/// Ambient sound control screen: one row per mode, with a chevron to the strength screen
/// for the modes that have one.
struct AmbientSoundScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Ambient Sound Control") {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            ForEach(ListeningMode.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    subtitle: headphones.state.level(for: option).map { String(localized: "Level \($0)") },
                    isActive: headphones.state.mode == option
                ) {
                    if option.hasLevel {
                        levelChevron(for: option)
                    }
                } action: {
                    headphones.select(option)
                }
            }
        }
    }

    /// Opens the strength screen for a mode.
    private func levelChevron(for mode: ListeningMode) -> some View {
        Button {
            screen = .level(mode)
        } label: {
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(String(localized: mode.title)) level"))
    }
}
