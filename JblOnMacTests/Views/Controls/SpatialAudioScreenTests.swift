@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct SpatialAudioScreenTests {
    private func controller(model name: String? = nil) -> HeadphoneController {
        let headphones = HeadphoneController()
        if let name {
            headphones.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
        }
        return headphones
    }

    @Test func spatialAudioListsEveryModeWhetherOrNotOneIsKnown() {
        let unknown = controller()
        let known = controller()
        known.state.spatialMode = SpatialAudioMode.allCases.first
        let box = Box(Screen.spatialAudio)
        let unknownSize = ViewHost.size(of: SpatialAudioScreen(headphones: unknown, screen: box.binding))
        let knownSize = ViewHost.size(of: SpatialAudioScreen(headphones: known, screen: box.binding))
        #expect(unknownSize.height > 0)
        #expect(unknownSize == knownSize)
    }

    @Test func spatialAndSmartScreensFollowTheirRowCounts() {
        let headphones = controller()
        let box = Box(Screen.spatialAudio)
        let spatial = ViewHost.size(of: SpatialAudioScreen(headphones: headphones, screen: box.binding)).height
        let smart = ViewHost.size(of: SmartAudioScreen(headphones: headphones, screen: box.binding)).height
        let spatialRows = SpatialAudioMode.allCases.count
        let smartRows = SmartAudioMode.allCases.count
        #expect((spatialRows < smartRows) == (spatial < smart))
        #expect((spatialRows == smartRows) == (spatial == smart))
    }
}
