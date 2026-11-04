@testable import JblOnMac

struct FakeClassicDevice: ClassicBluetoothDevice {
    var name: String?
    var address: String?
    var isConnected = false
    var isPaired = true
}

/// A `ClassicBluetooth` that records the calls and lets a test report results.
final class FakeClassicBluetooth: ClassicBluetooth {
    var onEvent: ((ClassicBluetoothEvent) -> Void)?
    var paired: [FakeClassicDevice] = []
    var known: [String: FakeClassicDevice] = [:]
    var pairingStarts = true
    var connectionStarts = true
    private(set) var inquiriesStarted = 0
    private(set) var inquiriesStopped = 0
    private(set) var pairingRequests: [String] = []
    private(set) var connectionRequests: [String] = []

    func pairedDevices() -> [any ClassicBluetoothDevice] {
        paired
    }

    func device(address: String) -> (any ClassicBluetoothDevice)? {
        known[address]
    }

    func startInquiry() {
        inquiriesStarted += 1
    }

    func stopInquiry() {
        inquiriesStopped += 1
    }

    func startPairing(address: String) -> Bool {
        pairingRequests.append(address)
        return pairingStarts
    }

    func openConnection(address: String) -> Bool {
        connectionRequests.append(address)
        return connectionStarts
    }

    func send(_ event: ClassicBluetoothEvent) {
        onEvent?(event)
    }
}
