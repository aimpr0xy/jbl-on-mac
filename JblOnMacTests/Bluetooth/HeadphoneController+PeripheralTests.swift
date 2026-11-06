import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct PeripheralTests {
        @Test func storedValueRepliesLandInTheState() {
            ControllerFixture.withController { controller in
                controller.apply(.balance(3))
                controller.apply(.listeningMode(.talkThru))
                #expect(controller.state.balance == 3)
                #expect(controller.state.mode == .talkThru)
            }
        }

        @Test func readingTheLinkSignalWithoutALinkLeavesItUnknown() {
            ControllerFixture.withController { controller in
                controller.readLinkRSSI()
                #expect(controller.linkRSSI == nil)
                #expect(controller.linkIdentifier == nil)
            }
        }

        @Test func leavingTheDeviceForgetsItsSignal() {
            ControllerFixture.withController { controller in
                controller.linkRSSI = -60
                controller.linkIdentifier = UUID()
                controller.deselect()
                #expect(controller.linkRSSI == nil)
                #expect(controller.linkIdentifier == nil)
            }
        }

        @Test func firmwareRepliesAreStoredAndSavedForNextTime() {
            ControllerFixture.withController { controller in
                controller.apply(.firmware("3.7.0"))
                controller.apply(.caseFirmware("1.0.0"))
                #expect(controller.state.info == DeviceInfo(firmware: "3.7.0", caseFirmware: "1.0.0"))
                #expect(controller.savedDeviceInfo == DeviceInfo(firmware: "3.7.0", caseFirmware: "1.0.0"))
            }
        }
    }
}
