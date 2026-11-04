@testable import JblOnMac
import SwiftUI
import Testing

/// Lays out `PopoverScreens`, not `ContentView`: its discovery calls into IOBluetooth, which
/// blocks on a Mac without Bluetooth, such as a CI runner.
@MainActor
struct ContentViewTests {
    private let device = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA:BB", isConnected: true)

    private func size(_ configure: (HeadphoneController) -> Void) -> CGSize {
        let controller = HeadphoneController()
        configure(controller)
        return ViewHost.size(of: PopoverScreens(headphones: controller))
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
        for status in [HeadphoneController.Status.idle, .scanning, .connecting] {
            let pending = size {
                $0.devices = [device]
                $0.selectedDevice = device
                $0.status = status
            }
            #expect(pending.height == list.height)
        }
    }

    @Test func selectedDeviceWithBluetoothOffShowsTheList() {
        let controls = size {
            $0.devices = [device]
            $0.selectedDevice = device
            $0.status = .connected
        }
        // The row grows by a "Bluetooth is off" subtitle, but the controls don't open.
        let pending = size {
            $0.devices = [device]
            $0.selectedDevice = device
            $0.status = .bluetoothOff
        }
        #expect(pending.height < controls.height)
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
