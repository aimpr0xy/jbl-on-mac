import SwiftUI

@main struct JblOnMac: App {
    @State private var headphones = HeadphoneController()

    var body: some Scene {
        MenuBarExtra {
            ContentView(headphones: headphones)
        } label: {
            Image("JblSymbol")
        }
        .menuBarExtraStyle(.window)
    }
}
