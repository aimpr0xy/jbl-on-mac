import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct CentralTests {
        @Test func bluetoothStateUpdatesAreReflectedInTheStatus() {
            ControllerFixture.withController { controller in
                let state = controller.central.state
                // With the radio on the controller starts scanning, which a test must not do.
                guard state != .poweredOn else { return }
                controller.centralManagerDidUpdateState(controller.central)
                #expect(controller.isBluetoothOff == (state == .poweredOff))
                #expect(controller.status == (state == .unauthorized ? .unauthorized : .bluetoothOff))
            }
        }
    }
}
