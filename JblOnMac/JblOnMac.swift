import SwiftUI

@main struct JblOnMac: App {
    @State private var headphones = HeadphoneController()

    var body: some Scene {
        MenuBarExtra("Listening Mode", systemImage: "headphones") {
            ContentView(headphones: headphones)
        }
        .menuBarExtraStyle(.window)
    }
}
