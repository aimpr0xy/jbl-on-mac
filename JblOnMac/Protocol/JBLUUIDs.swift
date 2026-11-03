import CoreBluetooth

/// Characteristics of the JBL BLE service.
enum JBLUUID {
    static let service = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0000")
    static let write = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0002")
    /// The Tune 230NC's connectable advertisement has no name macOS can see (it's only in the scan
    /// response), so it is recognized by its Google Fast Pair service data: the model id
    /// `96 C1 2E` in pairing mode, otherwise just `00 00`. Its other advertiser ("X185040")
    /// accepts connections but has no JBL service.
    static let fastPairService = CBUUID(string: "FE2C")
    static let tune230NCFastPairModel: [UInt8] = [0x96, 0xC1, 0x2E]
    static let tune230NCIdleFastPairData: [UInt8] = [0x00, 0x00]
    static let notify = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0001")
}
