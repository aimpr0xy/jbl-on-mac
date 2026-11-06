import AppKit
import SwiftUI

/// Owns the single About window so choosing About again brings it forward.
@MainActor
final class AboutWindow {
    static let shared = AboutWindow()

    private var window: NSWindow?

    /// The app icon from the asset catalog, falling back to whatever icon the app currently has.
    static var icon: NSImage {
        NSImage(named: "jbl-icon") ?? NSApp.applicationIconImage
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.title = "About"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // An agent app is never frontmost on its own, so activate it or the window opens behind.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // Activation is cooperative and can be denied when it comes from a menu action, so also
        // order the window front directly.
        window?.orderFrontRegardless()
    }
}

private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: AboutWindow.icon)
                .resizable()
                .frame(width: 96, height: 96)
            Text("JBL On Mac")
                .font(.title2.bold())
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Control your JBL headphones from the menu bar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let url = URL(string: "https://github.com/aimpr0xy/jbl-on-mac") {
                Link("GitHub", destination: url)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}
