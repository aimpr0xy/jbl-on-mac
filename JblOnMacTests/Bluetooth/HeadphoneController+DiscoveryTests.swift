@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct HeadphoneControllerDiscoveryTests {
        @Test func discoveryDoesNotRunWhileADeviceIsSelected() {
            let radio = FakeClassicBluetooth()
            ControllerFixture.withController(classicBluetooth: radio) { controller in
                controller.startDiscovery()
                #expect(radio.inquiriesStarted == 0)
                #expect(!controller.discovery.isDiscovering)
            }
        }

        @Test func discoveryRunsOnTheDeviceList() {
            let radio = FakeClassicBluetooth()
            ControllerFixture.withController(selecting: nil, classicBluetooth: radio) { controller in
                controller.startDiscovery()
                #expect(radio.inquiriesStarted == 1)
                controller.stopDiscovery()
                #expect(!controller.discovery.isDiscovering)
            }
        }

        @Test func refreshingPublishesTheDiscoveredList() {
            let radio = FakeClassicBluetooth()
            radio.paired = [FakeClassicDevice(name: "JBL Go", address: "A1")]
            ControllerFixture.withController(selecting: nil, classicBluetooth: radio) { controller in
                controller.refreshDevices()
                #expect(controller.devices.map(\.address) == ["A1"])
            }
        }

        @Test func connectingIsReportedByTheController() {
            let radio = FakeClassicBluetooth()
            radio.known["A1"] = FakeClassicDevice(name: "JBL Go", address: "A1")
            ControllerFixture.withController(selecting: nil, classicBluetooth: radio) { controller in
                controller.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
                #expect(controller.connectingAddress == "A1")
                #expect(radio.connectionRequests == ["A1"])
            }
        }
    }
}
