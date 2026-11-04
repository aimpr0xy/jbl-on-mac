@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct SectionTitleTests {
    @Test func sectionTitleIsPaddedText() {
        let size = ViewHost.size(of: SectionTitle("Sound"), width: 200)
        let bare = ViewHost.size(of: Text("Sound").font(.subheadline.weight(.semibold)), width: 200)
        #expect(size.height > bare.height)
        #expect(size.width > bare.width)
    }
}
