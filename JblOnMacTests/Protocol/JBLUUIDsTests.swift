import CoreBluetooth
@testable import JblOnMac
import Testing

struct JBLUUIDsTests {
    @Test func theJBLServiceAndItsCharacteristicsShareAPrefix() {
        let prefix = "65786365-6C70-6F69-6E74-2E636F6D000"
        #expect(JBLUUID.service.uuidString == prefix + "0")
        #expect(JBLUUID.notify.uuidString == prefix + "1")
        #expect(JBLUUID.write.uuidString == prefix + "2")
    }

    @Test func tune230NCIsRecognizedByItsFastPairData() {
        #expect(JBLUUID.fastPairService == CBUUID(string: "FE2C"))
        #expect(JBLUUID.tune230NCFastPairModel == [0x96, 0xC1, 0x2E])
        #expect(JBLUUID.tune230NCIdleFastPairData == [0x00, 0x00])
    }

    @Test func genericAccessIsTheStandard1800Service() {
        #expect(JBLUUID.genericAccess == CBUUID(string: "1800"))
        #expect(JBLUUID.genericAccess.uuidString == "1800")
    }
}
