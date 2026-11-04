import CoreBluetooth
import Foundation
@testable import JblOnMac
import os
import Testing

extension ControllerSuite {
    @MainActor
    struct CentralTests {
        @Test func theControllerIsTheCentralManagersDelegate() {
            ControllerFixture.withController { controller in
                #expect(controller.central.delegate === controller)
            }
        }

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

        @Test func unrelatedAdvertisementsAreLoggedAtDebugOnly() {
            #expect(HeadphoneController.discoveryLogLevel(for: .none) == .debug)
            #expect(HeadphoneController.discoveryLogLevel(for: .exact) == .default)
        }

        @Test func discoveryLogLineHoldsOnlyTheMatchingFields() {
            let line = HeadphoneController.discoveryLogLine(name: "JBL", rssi: -40, fastPairData: [0x01, 0xAB])
            #expect(line == "discovered name=JBL rssi=-40 fastPair=01ab")
            #expect(HeadphoneController.discoveryLogLine(name: nil, rssi: -9, fastPairData: nil)
                == "discovered name=nil rssi=-9 fastPair=nil")
        }
    }
}
