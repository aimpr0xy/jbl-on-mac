@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct SmartAudioScreenTests {
    private func controller(model name: String? = nil) -> HeadphoneController {
        let headphones = HeadphoneController()
        if let name {
            headphones.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
        }
        return headphones
    }

    @Test func smartAudioListsEveryModeWhetherOrNotOneIsKnown() {
        let unknown = controller()
        let known = controller()
        known.state.smartMode = SmartAudioMode.allCases.last
        let box = Box(Screen.smartAudio)
        let unknownSize = ViewHost.size(of: SmartAudioScreen(headphones: unknown, screen: box.binding))
        let knownSize = ViewHost.size(of: SmartAudioScreen(headphones: known, screen: box.binding))
        #expect(unknownSize.height > 0)
        #expect(unknownSize == knownSize)
    }
}
