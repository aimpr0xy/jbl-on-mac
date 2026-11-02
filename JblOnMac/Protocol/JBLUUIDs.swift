import CoreBluetooth

/// Characteristics of the JBL BLE service.
enum JBLUUID {
    static let write = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0002")
    static let notify = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0001")
}
