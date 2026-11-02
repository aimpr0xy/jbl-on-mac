import SwiftUI

/// Plain title bar used by the device list.
struct ScreenHeader<Trailing: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

/// Title bar with a back chevron, used by every screen after the device list.
struct BackHeader<Trailing: View>: View {
    let title: LocalizedStringResource
    var backLabel: LocalizedStringResource = "Back"
    let onBack: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.callout.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backLabel)

            Text(title)
                .font(.headline)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

/// The chevron shown at the trailing edge of rows that open another screen.
struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}
