import Testing
@testable import JblOnMac

/// Dropping devices from the list once they stop turning up in inquiries.
struct NearbyTrackerTests {
    /// Runs one inquiry that finds `found`, and returns who the tracker says is gone.
    private func inquiry(_ tracker: inout NearbyTracker, finding found: [String]) -> [String] {
        found.forEach { tracker.saw($0) }
        return tracker.inquiryCompleted()
    }

    @Test func keepsADeviceThatIsFoundEveryTime() {
        var tracker = NearbyTracker()
        for _ in 0..<10 {
            #expect(inquiry(&tracker, finding: ["A"]).isEmpty)
        }
    }

    @Test func toleratesMissedInquiriesUpToTheLimit() {
        var tracker = NearbyTracker()
        _ = inquiry(&tracker, finding: ["A"])
        for _ in 0..<NearbyTracker.allowedMisses {
            #expect(inquiry(&tracker, finding: []).isEmpty)
        }
    }

    @Test func dropsADeviceOnceItMissedTooMany() {
        var tracker = NearbyTracker()
        _ = inquiry(&tracker, finding: ["A"])
        for _ in 0..<NearbyTracker.allowedMisses {
            _ = inquiry(&tracker, finding: [])
        }
        #expect(inquiry(&tracker, finding: []) == ["A"])
        // Reported once, not on every later inquiry.
        #expect(inquiry(&tracker, finding: []).isEmpty)
    }

    @Test func aDeviceThatIsFoundAgainStays() {
        var tracker = NearbyTracker()
        _ = inquiry(&tracker, finding: ["A"])
        _ = inquiry(&tracker, finding: [])
        _ = inquiry(&tracker, finding: ["A"])
        for _ in 0..<NearbyTracker.allowedMisses {
            #expect(inquiry(&tracker, finding: []).isEmpty)
        }
    }

    @Test func devicesAreTrackedSeparately() {
        var tracker = NearbyTracker()
        _ = inquiry(&tracker, finding: ["A", "B"])
        for _ in 0..<NearbyTracker.allowedMisses {
            _ = inquiry(&tracker, finding: ["B"])
        }
        #expect(inquiry(&tracker, finding: ["B"]) == ["A"])
    }
}
