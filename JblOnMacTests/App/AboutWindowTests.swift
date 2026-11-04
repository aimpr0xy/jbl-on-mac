import AppKit
@testable import JblOnMac
import Testing

@MainActor
struct AboutWindowTests {
    private func aboutWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.title == "About" }
    }

    @Test func aboutWindowOpensOnceAndIsReused() throws {
        AboutWindow.shared.show()
        AboutWindow.shared.show()
        let windows = aboutWindows()
        defer { windows.forEach { $0.close() } }
        #expect(windows.count == 1)
        let window = try #require(windows.first)
        #expect(window.isVisible)
        #expect(window.styleMask.contains(.closable))
        #expect(!window.isReleasedWhenClosed)
    }
}
