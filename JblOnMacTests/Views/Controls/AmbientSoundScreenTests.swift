@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct AmbientSoundScreenTests {
    private func controller(model name: String? = nil) -> HeadphoneController {
        let headphones = HeadphoneController()
        if let name {
            headphones.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
        }
        return headphones
    }

    private func ambient(_ headphones: HeadphoneController) -> CGSize {
        ViewHost.size(of: AmbientSoundScreen(headphones: headphones, screen: Box(Screen.ambientSound).binding))
    }

    @Test func ambientRowsGrowWhenLevelsAreReported() {
        let bare = controller()
        let oneLevel = controller()
        oneLevel.state.noiseCancelingLevel = 3
        let bothLevels = controller()
        bothLevels.state.noiseCancelingLevel = 3
        bothLevels.state.ambientAwareLevel = 5

        let bareHeight = ambient(bare).height
        #expect(bareHeight > 0)
        #expect(ambient(oneLevel).height > bareHeight)
        #expect(ambient(bothLevels).height > ambient(oneLevel).height)
    }

    @Test func ambientActiveModeDoesNotChangeLayout() {
        let off = controller()
        off.state.mode = .off
        let active = controller()
        active.state.mode = .talkThru
        #expect(ambient(off) == ambient(active))
    }
}
