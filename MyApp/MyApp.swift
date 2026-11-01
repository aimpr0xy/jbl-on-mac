import SwiftUI

@main struct MyApp: App {
    @State private var mode: ListeningMode = .noiseCanceling

    var body: some Scene {
        MenuBarExtra("Listening Mode", systemImage: mode.systemImage) {
            ContentView(mode: $mode)
        }
        .menuBarExtraStyle(.window)
    }
}
