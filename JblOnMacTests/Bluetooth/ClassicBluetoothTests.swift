@testable import JblOnMac
import Testing

@MainActor
struct ClassicBluetoothTests {
    @Test func reportsEventsToTheListener() {
        let classic = IOBluetoothClassic()
        var events: [ClassicBluetoothEvent] = []
        classic.onEvent = { events.append($0) }
        classic.deviceInquiryComplete(nil, error: 0, aborted: true)
        classic.connectionComplete(nil, status: 0)
        classic.connectionComplete(nil, status: 1)
        guard events.count == 3,
              case .inquiryCompleted(aborted: true) = events[0],
              case .connectionFinished(succeeded: true) = events[1],
              case .connectionFinished(succeeded: false) = events[2] else {
            Issue.record("unexpected events")
            return
        }
    }

    @Test func pairingFailureHasNoAddress() {
        let classic = IOBluetoothClassic()
        var address: String? = "unset"
        classic.onEvent = {
            if case let .pairingFinished(found) = $0 {
                address = found
            }
        }
        classic.devicePairingFinished(nil, error: 1)
        #expect(address == nil)
    }

    @Test func rejectsMalformedAddresses() {
        let classic = IOBluetoothClassic()
        #expect(classic.device(address: "not an address") == nil)
        #expect(!classic.openConnection(address: "not an address"))
        #expect(!classic.startPairing(address: "not an address"))
    }
}
