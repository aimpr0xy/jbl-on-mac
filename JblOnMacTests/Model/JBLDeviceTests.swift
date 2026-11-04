import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

struct JBLDeviceTests {
    @Test func deviceIdentityIsItsAddress() {
        let device = JBLDevice(name: "A", address: "AA:BB", isConnected: false)
        #expect(device.id == "AA:BB")
        #expect(device != JBLDevice(name: "A", address: "AA:BB", isConnected: true))
        #expect(Set([device, device]).count == 1)
    }
}
