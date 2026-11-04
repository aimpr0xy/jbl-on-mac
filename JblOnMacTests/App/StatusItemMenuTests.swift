import AppKit
@testable import JblOnMac
import Testing

@MainActor
struct StatusItemMenuTests {
    private func aboutWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.title == "About" }
    }

    @Test func statusItemMenuAboutActionShowsTheAboutWindow() {
        StatusItemMenu.shared.perform(NSSelectorFromString("showAbout"))
        let windows = aboutWindows()
        defer { windows.forEach { $0.close() } }
        #expect(windows.contains { $0.isVisible })
    }

    @Test func monitorPassesThroughEventsNotForTheStatusItem() throws {
        StatusItemMenu.shared.install()
        StatusItemMenu.shared.install()
        let click = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w",
            isARepeat: false, keyCode: 13
        ))
        // Neither event is handled by the menu, so both are still delivered normally.
        NSApp.sendEvent(click)
        NSApp.sendEvent(key)
        #expect(NSApp.windows.allSatisfy { $0.title != "About" || !$0.isVisible })
    }
}
