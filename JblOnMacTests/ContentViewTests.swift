@testable import JblOnMac
import SwiftUI
import Testing

/// ContentView starts a Bluetooth inquiry that keeps calling its controller, so the controllers
/// must outlive the test.
@MainActor
private var keptAlive: [HeadphoneController] = []

@MainActor
struct ContentViewTests {
    private let device = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA:BB", isConnected: true)

    private func size(_ configure: (HeadphoneController) -> Void) -> CGSize {
        let controller = HeadphoneController()
        configure(controller)
        keptAlive.append(controller)
        return ViewHost.size(of: ContentView(headphones: controller))
    }

    @Test func usesThePopoverWidth() {
        #expect(size { _ in }.width == 280)
    }

    @Test func connectedDeviceShowsItsControlsInsteadOfTheList() {
        let list = size { $0.devices = [device] }
        let controls = size {
            $0.devices = [device]
            $0.selectedDevice = device
            $0.status = .connected
            $0.state.smartMode = .audio
            $0.state.balance = 2
            $0.state.equalizer = .jazz
        }
        #expect(controls.height > list.height)
    }

    @Test func selectedDeviceThatIsNotConnectedYetShowsTheList() {
        let list = size { $0.devices = [device] }
        for status in [HeadphoneController.Status.idle, .scanning, .connecting, .bluetoothOff] {
            let pending = size {
                $0.devices = [device]
                $0.selectedDevice = device
                $0.status = status
            }
            #expect(pending.height == list.height)
        }
    }

    @Test func connectedStatusWithoutADeviceShowsTheList() {
        let list = size { $0.devices = [device] }
        let noDevice = size {
            $0.devices = [device]
            $0.status = .connected
        }
        #expect(noDevice.height == list.height)
    }
}
