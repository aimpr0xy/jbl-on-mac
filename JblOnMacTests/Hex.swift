import Foundation

/// Parses a packet written the way PacketLogger shows it, e.g. `"AA 91 01 11"`.
func bytes(_ hex: String) -> [UInt8] {
    hex.split(separator: " ").map { UInt8($0, radix: 16)! }
}
