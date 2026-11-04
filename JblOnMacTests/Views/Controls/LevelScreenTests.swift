@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct LevelScreenTests {
    private func controller(model name: String? = nil) -> HeadphoneController {
        let headphones = HeadphoneController()
        if let name {
            headphones.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
        }
        return headphones
    }

    @Test func levelScreenShowsTheStrengthOnceKnown() {
        let unknown = controller()
        let known = controller()
        known.state.noiseCancelingLevel = 7
        known.state.ambientAwareLevel = 1
        let box = Box(Screen.level(.noiseCanceling))
        for mode in [ListeningMode.noiseCanceling, .ambientAware] {
            let without = ViewHost.size(of: LevelScreen(headphones: unknown, mode: mode, screen: box.binding))
            let with = ViewHost.size(of: LevelScreen(headphones: known, mode: mode, screen: box.binding))
            #expect(without.height > 0)
            #expect(with.height >= without.height)
        }
    }

    @Test func levelScreenForModesWithoutStrengthStillRenders() {
        let headphones = controller()
        headphones.state.noiseCancelingLevel = 2
        let box = Box(Screen.level(.talkThru))
        let size = ViewHost.size(of: LevelScreen(headphones: headphones, mode: .talkThru, screen: box.binding))
        #expect(size.height > 0)
    }
}
