/// Remembers in which inquiry each nearby device was last seen, so devices that went out of range
/// can be dropped from the list. One missed inquiry isn't enough, since an inquiry can miss a
/// device that is still there.
struct NearbyTracker {
    /// How many whole inquiries in a row a device can be missed before it counts as gone.
    static let allowedMisses = 2

    private var inquiry = 0
    private var lastSeen: [String: Int] = [:]

    /// Records a device found by the running inquiry.
    mutating func saw(_ address: String) {
        lastSeen[address] = inquiry
    }

    /// Call when an inquiry ran to the end. Returns the addresses to stop listing.
    mutating func inquiryCompleted() -> [String] {
        // Inquiries that ran since the one that last found each device.
        let gone = lastSeen.filter { inquiry - $0.value > Self.allowedMisses }.map(\.key)
        inquiry += 1
        for address in gone {
            lastSeen[address] = nil
        }
        return gone
    }
}
