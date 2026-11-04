@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct ScreenHeaderTests {
    @Test func screenHeaderPlacesTrailingContent() {
        let plain = ViewHost.size(of: ScreenHeader(title: "Title") { EmptyView() })
        let tall = ViewHost.size(of: ScreenHeader(title: "Title") { Color.clear.frame(width: 10, height: 60) })
        #expect(plain.height > 0)
        #expect(tall.height > plain.height)
    }

    @Test func backHeaderHasAButtonAndTrailingContent() {
        let plain = ViewHost.size(of: BackHeader(title: "Title", onBack: {}, trailing: { EmptyView() }))
        let custom = ViewHost.size(of: BackHeader(
            title: "Title", backLabel: "Back to devices", onBack: {},
            trailing: { Color.clear.frame(width: 10, height: 60) }
        ))
        #expect(plain.height >= 22)
        #expect(custom.height > plain.height)
    }

    @Test func disclosureChevronHasAnIntrinsicSize() {
        let size = ViewHost.size(of: DisclosureChevron())
        #expect(size.width > 0)
        #expect(size.height > 0)
    }
}
