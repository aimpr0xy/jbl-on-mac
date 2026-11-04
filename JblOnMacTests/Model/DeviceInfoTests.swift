import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

struct DeviceInfoTests {
    @Test func setStoresOnlyTheFirmwareRevision() {
        var info = DeviceInfo()
        let storedFirmware = info.set("1.2.3", for: DeviceInfo.firmwareRevision)
        #expect(storedFirmware)
        #expect(info.firmware == "1.2.3")
        let storedOther = info.set("other", for: CBUUID(string: "2A27"))
        #expect(!storedOther)
        #expect(info.firmware == "1.2.3")
        #expect(info.caseFirmware == nil)
        #expect(DeviceInfo.characteristics == [DeviceInfo.firmwareRevision])
        #expect(DeviceInfo.service == CBUUID(string: "180A"))
    }

    @Test func stringTrimsNulPaddingAndWhitespace() {
        #expect(DeviceInfo.string(from: Data("1.0.4".utf8)) == "1.0.4")
        #expect(DeviceInfo.string(from: Data([0x31, 0x2E, 0x30, 0x00, 0x00])) == "1.0")
        #expect(DeviceInfo.string(from: Data(" v2 \n".utf8)) == "v2")
        #expect(DeviceInfo.string(from: Data()) == "")
    }

    @Test func stringIsEmptyForInvalidUTF8() {
        // A value that isn't valid text is treated as missing rather than shown garbled.
        #expect(DeviceInfo.string(from: Data([0x41, 0xFF, 0x42])) == "")
    }

    @Test func logDescription() {
        #expect(DeviceInfo().logDescription == nil)
        #expect(DeviceInfo(firmware: "1.0").logDescription == "firmware=1.0")
        #expect(DeviceInfo(caseFirmware: "2.0").logDescription == "case_firmware=2.0")
        #expect(DeviceInfo(firmware: "1.0", caseFirmware: "2.0").logDescription
            == "firmware=1.0 case_firmware=2.0")
    }

    @Test func codableRoundTrip() throws {
        let info = DeviceInfo(firmware: "1.0", caseFirmware: nil)
        let decoded = try JSONDecoder().decode(DeviceInfo.self, from: JSONEncoder().encode(info))
        #expect(decoded == info)
    }
}
