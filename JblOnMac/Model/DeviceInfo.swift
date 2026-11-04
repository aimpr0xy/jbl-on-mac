import CoreBluetooth
import Foundation

/// What the selected headphones report about themselves. The JBL Tune Beam 2 only offers the
/// firmware revision, through the standard Bluetooth Device Information service; the Tune 230NC
/// reports its earbud and case firmware in its own replies instead. Nil until read.
struct DeviceInfo: Codable, Equatable {
    var firmware: String?
    var caseFirmware: String?

    /// Device Information service and the firmware revision characteristic read from it.
    static let service = CBUUID(string: "180A")
    static let firmwareRevision = CBUUID(string: "2A26")
    static let characteristics = [firmwareRevision]

    /// Stores the value of one Device Information characteristic. Returns false for other
    /// characteristics.
    mutating func set(_ value: String, for characteristic: CBUUID) -> Bool {
        guard characteristic == Self.firmwareRevision else { return false }
        firmware = value
        return true
    }

    /// Decodes a characteristic value. They are UTF-8 strings, sometimes padded with NUL bytes.
    static func string(from data: Data) -> String {
        (String(bytes: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
    }

    /// Short form for log lines, or nil if no firmware version has been read yet.
    var logDescription: String? {
        let parts = [firmware.map { "firmware=\($0)" }, caseFirmware.map { "case_firmware=\($0)" }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
