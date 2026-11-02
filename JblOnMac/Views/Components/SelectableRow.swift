import SwiftUI

/// A Control Center–style row: a circular icon badge (accent-filled when active), a title,
/// and an optional trailing view. The whole row is the click target and highlights on hover.
struct SelectableRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    let isActive: Bool
    @ViewBuilder let trailing: Trailing
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering && isEnabled ? Color.primary.opacity(0.08) : .clear)
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
