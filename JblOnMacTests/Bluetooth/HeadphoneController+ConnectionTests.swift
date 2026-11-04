import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct ConnectionTests {
        @Test(arguments: [
            ("JBL Tune 230NC TWS", true),
            ("jbl tune 230nc tws", true),
            ("JBL Tune 230NC TWS-LE", true),
            ("JBL Tune Beam 2", false),
            ("Some Speaker", false)
        ])
        func exactMatchComparesTheNameWithAnOptionalLESuffix(name: String, expected: Bool) {
            ControllerFixture.withController { controller in
                #expect(controller.matchesSelectedDeviceExactly(name: name) == expected)
            }
        }

        @Test(arguments: [
            ("JBL Tune 230NC TWS", true),
            ("JBL Tune Beam 2", true),
            ("my jbl flip", true),
            ("Some Speaker", false)
        ])
        func anyJBLIsAFallbackMatch(name: String, expected: Bool) {
            ControllerFixture.withController { controller in
                #expect(controller.matchesSelectedDevice(name: name) == expected)
            }
        }

        @Test func nameMatchPrefersExactOverFallback() {
            ControllerFixture.withController { controller in
                #expect(controller.nameMatch(for: "JBL Tune 230NC TWS-LE") == .exact)
                #expect(controller.nameMatch(for: "JBL Flip 6") == .fallback)
                #expect(controller.nameMatch(for: "Keyboard") == .none)
                #expect(controller.nameMatch(for: nil) == .none)
            }
        }

        @Test func nothingMatchesWithoutASelectedDevice() {
            ControllerFixture.withController(selecting: nil) { controller in
                #expect(!controller.matchesSelectedDeviceExactly(name: "JBL Tune 230NC TWS"))
                #expect(!controller.matchesSelectedDevice(name: "JBL Tune 230NC TWS"))
                #expect(controller.nameMatch(for: "JBL Tune 230NC TWS") == .none)
            }
        }

        @Test func deselectingTheLinkDropsEverythingInFlight() {
            ControllerFixture.withController { controller in
                controller.run(.send(.setBalance(1)))
                controller.run(.uploadEqualizer(.club))
                controller.run(.uploadEqualizer(.vocal))
                controller.run(.notified(bytes("AA 43 AF 03")))
                #expect(controller.transferTimer != nil)
                controller.disconnect()
                #expect(controller.pipeline == CommandPipeline())
                #expect(controller.transferTimer == nil)
                #expect(controller.machine.current == nil)
                #expect(controller.machine.phase == .idle)
            }
        }

        @Test func scanningCannotStartWithoutBluetoothAccess() {
            ControllerFixture.withController { controller in
                let allowed = CBCentralManager.authorization == .allowedAlways
                guard !allowed || controller.central.state != .poweredOn else { return }
                controller.startScanning()
                if !allowed {
                    #expect(controller.status == .unauthorized)
                } else {
                    #expect(controller
                        .status == (controller.central.state == .unauthorized ? .unauthorized : .bluetoothOff))
                }
            }
        }
    }
}
