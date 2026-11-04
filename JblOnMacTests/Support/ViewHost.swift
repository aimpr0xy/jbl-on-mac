import AppKit
import SwiftUI

/// A value a test can bind to a SwiftUI `@Binding` and read back afterwards.
@MainActor
final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var binding: Binding<Value> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

/// Hosts a SwiftUI view in AppKit so its `body` really runs and it gets laid out.
@MainActor
enum ViewHost {
    /// The size the view wants at the app's popover width. A row that only shows once the
    /// headphones report a value makes the view taller, so tests compare heights between states.
    static func size(of view: some View, width: CGFloat = 280) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }
}
