@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct SelectableRowTests {
    private func row(
        subtitle: String? = nil, active: Bool = false, busy: Bool = false, enabled: Bool = true,
        dark: Bool = false
    ) -> CGSize {
        let view = SelectableRow(
            systemImage: "headphones", title: "Title", subtitle: subtitle, isActive: active, isBusy: busy
        ) {
            EmptyView()
        } action: {}
            .disabled(!enabled)
            .environment(\.colorScheme, dark ? .dark : .light)
        return ViewHost.size(of: view)
    }

    @Test func selectableRowGrowsWithASubtitle() {
        let plain = row()
        #expect(plain.height > 24)
        #expect(row(subtitle: "More").height > plain.height)
    }

    @Test func selectableRowKeepsItsSizeAcrossStates() {
        let plain = row()
        #expect(row(active: true) == plain)
        #expect(row(enabled: false) == plain)
        #expect(row(dark: true) == plain)
        #expect(row(active: true, busy: true).height == plain.height)
        #expect(row(busy: true, dark: true).height == plain.height)
    }

    @Test func trailingViewIsRendered() {
        let view = SelectableRow(systemImage: "phone", title: "Calls", isActive: false) {
            Color.clear.frame(width: 10, height: 80)
        } action: {}
        #expect(ViewHost.size(of: view).height >= 80)
    }
}
