import AppKit

/// Adds a right-click menu to the `MenuBarExtra` icon. SwiftUI doesn't expose the status item,
/// so this watches for right clicks that land on the status bar window and shows the menu there.
@MainActor
final class StatusItemMenu: NSObject {
    static let shared = StatusItemMenu()

    private var monitor: Any?
    private let menu = NSMenu()

    func install() {
        guard monitor == nil else { return }

        let about = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.items = [about, quitItem]

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .rightMouseDown:
                // The status item's window is a private NSStatusBarWindow.
                guard let window = event.window, String(describing: type(of: window)).contains("StatusBar"),
                      let view = window.contentView else { return event }
                NSMenu.popUpContextMenu(menu, with: event, for: view)
                return nil
            case .keyDown:
                // No main menu in an agent app, so handle ⌘Q while the popup is key.
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.charactersIgnoringModifiers == "q" {
                    quit()
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    @objc private func showAbout() {
        AboutWindow.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
