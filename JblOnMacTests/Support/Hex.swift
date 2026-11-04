import Foundation
@testable import JblOnMac
import Testing

/// Parses a packet written the way PacketLogger shows it, e.g. `"AA 91 01 11"`.
func bytes(_ hex: String) -> [UInt8] {
    hex.split(separator: " ").map { UInt8($0, radix: 16)! }
}

/// A notification and what it should decode to.
struct ReplyCase: CustomTestStringConvertible {
    let name: String
    let hex: String
    let replies: [JBLReply]
    var testDescription: String {
        name
    }
}
