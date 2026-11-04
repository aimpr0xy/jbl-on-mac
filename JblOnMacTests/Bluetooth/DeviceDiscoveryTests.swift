@testable import JblOnMac
import Testing

@MainActor
struct DeviceDiscoveryTests {
    private let radio = FakeClassicBluetooth()
    private let discovery: DeviceDiscovery

    init() {
        discovery = DeviceDiscovery(bluetooth: radio)
    }

    private func device(_ name: String?, _ address: String?, connected: Bool = false,
                        paired: Bool = true) -> FakeClassicDevice {
        FakeClassicDevice(name: name, address: address, isConnected: connected, isPaired: paired)
    }

    // MARK: - The list

    @Test func listsOnlyJBLNames() {
        radio.paired = [device("JBL Tune 230NC TWS", "A1"), device("Magic Mouse", "A2"), device(nil, "A3")]
        discovery.refresh()
        #expect(discovery.devices.map(\.address) == ["A1"])
    }

    @Test func jblMatchingIgnoresCase() {
        radio.paired = [device("my jbl buds", "A1")]
        discovery.refresh()
        #expect(discovery.devices.map(\.name) == ["my jbl buds"])
    }

    @Test func skipsDevicesWithoutAnAddress() {
        radio.paired = [device("JBL Go", nil)]
        discovery.refresh()
        #expect(discovery.devices.isEmpty)
    }

    @Test func connectedDevicesComeFirstThenByName() {
        radio.paired = [
            device("JBL C", "A3"), device("JBL B", "A2", connected: true),
            device("JBL A", "A1"), device("JBL D", "A4", connected: true)
        ]
        discovery.refresh()
        #expect(discovery.devices.map(\.name) == ["JBL B", "JBL D", "JBL A", "JBL C"])
        #expect(discovery.devices.map(\.isConnected) == [true, true, false, false])
    }

    @Test func mergesPairedAndNearbyByAddress() {
        radio.paired = [device("JBL Paired", "A1"), device("JBL Both", "A2", connected: true)]
        radio.send(.deviceFound(device("JBL Nearby", "A3", paired: false)))
        radio.send(.deviceFound(device("JBL Both", "A2")))
        discovery.refresh()
        #expect(discovery.devices.map(\.address).sorted() == ["A1", "A2", "A3"])
        // The paired entry wins over the nearby one with the same address.
        #expect(discovery.devices.first { $0.address == "A2" }?.isConnected == true)
    }

    @Test func nearbyNonJBLDevicesAreIgnored() {
        radio.send(.deviceFound(device("Keyboard", "A1")))
        discovery.refresh()
        #expect(discovery.devices.isEmpty)
    }

    // MARK: - Nearby devices leaving

    @Test func inquiryCompletionRefreshesTheList() {
        radio.send(.deviceFound(device("JBL Go", "A1")))
        radio.send(.inquiryCompleted(aborted: false))
        #expect(discovery.devices.map(\.address) == ["A1"])
    }

    @Test func abortedInquiryDoesNotRefresh() {
        radio.send(.deviceFound(device("JBL Go", "A1")))
        radio.send(.inquiryCompleted(aborted: true))
        #expect(discovery.devices.isEmpty)
    }

    @Test func aDeviceThatStopsTurningUpIsDropped() {
        radio.send(.deviceFound(device("JBL Go", "A1")))
        radio.send(.inquiryCompleted(aborted: false))
        for _ in 0 ... NearbyTracker.allowedMisses {
            radio.send(.inquiryCompleted(aborted: false))
        }
        #expect(discovery.devices.isEmpty)
    }

    // MARK: - The connecting spinner

    @Test func connectingEndsOnceTheDeviceShowsUpConnected() {
        radio.known["A1"] = device("JBL Go", "A1")
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        #expect(discovery.connectingAddress == "A1")
        radio.paired = [device("JBL Go", "A1")]
        discovery.refresh()
        #expect(discovery.connectingAddress == "A1")
        radio.paired = [device("JBL Go", "A1", connected: true)]
        discovery.refresh()
        #expect(discovery.connectingAddress == nil)
    }

    @Test func connectingContinuesWhenAnotherDeviceIsConnected() {
        radio.known["A1"] = device("JBL Go", "A1")
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        radio.paired = [device("JBL Go", "A1"), device("JBL Flip", "A2", connected: true)]
        discovery.refresh()
        #expect(discovery.connectingAddress == "A1")
    }

    // MARK: - Connecting

    @Test func connectingAPairedDeviceOpensTheConnection() {
        radio.known["A1"] = device("JBL Go", "A1")
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        #expect(radio.connectionRequests == ["A1"])
        #expect(radio.pairingRequests.isEmpty)
        radio.send(.connectionFinished(succeeded: true))
        #expect(discovery.connectingAddress == nil)
    }

    @Test func connectingAnUnpairedDevicePairsFirst() {
        radio.known["A1"] = device("JBL Go", "A1", paired: false)
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        #expect(radio.pairingRequests == ["A1"])
        #expect(radio.connectionRequests.isEmpty)
        #expect(discovery.connectingAddress == "A1")
        radio.send(.pairingFinished(address: "A1"))
        #expect(radio.connectionRequests == ["A1"])
        #expect(discovery.connectingAddress == "A1")
    }

    @Test func connectingAnUnknownDeviceDoesNothing() {
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        #expect(discovery.connectingAddress == nil)
        #expect(radio.connectionRequests.isEmpty)
    }

    @Test func failedPairingEndsConnecting() {
        radio.known["A1"] = device("JBL Go", "A1", paired: false)
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        radio.send(.pairingFinished(address: nil))
        #expect(discovery.connectingAddress == nil)
        #expect(radio.connectionRequests.isEmpty)
    }

    @Test func pairingThatCannotStartEndsConnecting() {
        radio.known["A1"] = device("JBL Go", "A1", paired: false)
        radio.pairingStarts = false
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        #expect(discovery.connectingAddress == nil)
    }

    @Test func connectionThatCannotStartEndsConnecting() {
        radio.known["A1"] = device("JBL Go", "A1")
        radio.connectionStarts = false
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        #expect(discovery.connectingAddress == nil)
    }

    @Test func failedConnectionEndsConnecting() {
        radio.known["A1"] = device("JBL Go", "A1")
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        radio.send(.connectionFinished(succeeded: false))
        #expect(discovery.connectingAddress == nil)
    }

    // MARK: - Starting and stopping

    @Test func startingTwiceRunsOneInquiry() {
        discovery.start()
        discovery.start()
        #expect(radio.inquiriesStarted == 1)
    }

    @Test func stoppingStopsTheInquiry() {
        discovery.start()
        discovery.stop()
        #expect(radio.inquiriesStopped == 1)
        #expect(!discovery.isDiscovering)
    }

    @Test func connectingPausesDiscoveryAndResumesAfterwards() {
        radio.known["A1"] = device("JBL Go", "A1")
        discovery.start()
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        #expect(!discovery.isDiscovering)
        radio.send(.connectionFinished(succeeded: true))
        #expect(discovery.isDiscovering)
        #expect(radio.inquiriesStarted == 2)
    }

    @Test func connectingDoesNotStartDiscoveryThatWasNotRunning() {
        radio.known["A1"] = device("JBL Go", "A1")
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        radio.send(.connectionFinished(succeeded: true))
        #expect(!discovery.isDiscovering)
        #expect(radio.inquiriesStarted == 0)
    }

    @Test func startingWhileConnectingWaitsForTheConnectionToEnd() {
        radio.known["A1"] = device("JBL Go", "A1")
        discovery.connect(JBLDevice(name: "JBL Go", address: "A1", isConnected: false))
        discovery.start()
        #expect(radio.inquiriesStarted == 0)
        radio.send(.connectionFinished(succeeded: true))
        #expect(radio.inquiriesStarted == 1)
    }

    @Test func anotherInquiryRunsAfterThePause() async {
        discovery.pause = .milliseconds(1)
        discovery.start()
        radio.send(.inquiryCompleted(aborted: false))
        for _ in 0 ..< 200 where radio.inquiriesStarted < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(radio.inquiriesStarted == 2)
    }

    @Test func stoppingCancelsThePendingInquiry() async {
        discovery.pause = .milliseconds(20)
        discovery.start()
        radio.send(.inquiryCompleted(aborted: false))
        discovery.stop()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(radio.inquiriesStarted == 1)
    }
}
