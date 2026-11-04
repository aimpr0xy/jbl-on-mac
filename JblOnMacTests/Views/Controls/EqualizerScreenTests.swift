@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct EqualizerScreenTests {
    private func controller(model name: String? = nil) -> HeadphoneController {
        let headphones = HeadphoneController()
        if let name {
            headphones.selectedDevice = JBLDevice(name: name, address: "AA:BB", isConnected: true)
        }
        return headphones
    }

    @Test func equalizerShowsTheModelsPresets() {
        let beam = controller(model: "JBL Tune Beam 2")
        let earbuds = controller(model: "JBL Tune 230NC TWS")
        #expect(beam.model.equalizerPresets.count > earbuds.model.equalizerPresets.count)
        let box = Box(Screen.equalizer)
        let beamHeight = ViewHost.size(of: EqualizerScreen(headphones: beam, screen: box.binding)).height
        let earbudHeight = ViewHost.size(of: EqualizerScreen(headphones: earbuds, screen: box.binding)).height
        #expect(beamHeight > earbudHeight)
    }

    @Test func equalizerLayoutIgnoresTheActivePreset() {
        let none = controller(model: "JBL Tune 230NC TWS")
        let some = controller(model: "JBL Tune 230NC TWS")
        some.state.equalizer = .club
        let box = Box(Screen.equalizer)
        #expect(ViewHost.size(of: EqualizerScreen(headphones: none, screen: box.binding))
            == ViewHost.size(of: EqualizerScreen(headphones: some, screen: box.binding)))
    }
}
