import SwiftUI

@main struct JblOnMac: App {
    @State private var headphones = HeadphoneController()

    init() {
        // The menu bar icon only needs to exist before the first click.
        DispatchQueue.main.async { StatusItemMenu.shared.install() }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(headphones: headphones)
        } label: {
            Image("JblSymbol")
        }
        .menuBarExtraStyle(.window)
    }
}
