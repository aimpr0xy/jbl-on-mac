import SwiftUI

struct SectionTitle: View {
    let title: LocalizedStringResource

    init(_ title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }
}
