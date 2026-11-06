@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct DeveloperModeScreenTests {
    private func screen(rssi: Int? = nil, identifier: UUID? = nil, info: DeviceInfo = DeviceInfo()) -> CGSize {
        let controller = HeadphoneController()
        let device = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA:BB", isConnected: true)
        controller.selectedDevice = device
        controller.linkRSSI = rssi
        controller.linkIdentifier = identifier
        controller.state.info = info
        let binding = Box(Screen.developerMode).binding
        return ViewHost.size(of: DeveloperModeScreen(headphones: controller, device: device, screen: binding))
    }

    @Test func screenListsNameSignalAndAddress() {
        // Header plus three labelled values.
        #expect(screen().height > 100)
        #expect(screen(rssi: -62).height == screen().height)
    }

    @Test func firmwareVersionsAppearOnceReported() {
        let none = screen()
        let earbuds = screen(info: DeviceInfo(firmware: "1.2.3"))
        let withCase = screen(info: DeviceInfo(firmware: "1.2.3", caseFirmware: "4.5.6"))
        #expect(earbuds.height > none.height)
        #expect(withCase.height > earbuds.height)
        // Each version has a row of its own, so the case's shows without the earbuds'.
        #expect(screen(info: DeviceInfo(caseFirmware: "4.5.6")).height > none.height)
    }

    @Test func leIdentifierRowShowsOnceTheLinkIsKnown() {
        // The row is always there; a known identifier only changes its text, not the layout.
        #expect(screen(identifier: UUID()).height == screen().height)
    }

    @Test func signalReadsAsDecibelsOrNotAvailable() {
        #expect(DeveloperModeScreen.describe(rssi: -62) == "-62 dBm")
        #expect(DeveloperModeScreen.describe(rssi: nil) == "n/a")
    }
}
