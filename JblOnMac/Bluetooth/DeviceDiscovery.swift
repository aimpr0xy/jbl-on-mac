import Foundation
import os

/// Finds the JBL products around, through classic Bluetooth, and pairs and connects them through
/// macOS. The list is rebuilt from the paired devices plus whatever the inquiry found nearby.
@MainActor
@Observable
final class DeviceDiscovery {
    /// How long the list rests between two refreshes.
    static let pauseBetweenInquiries = Duration.seconds(10)

    var devices: [JBLDevice] = []
    /// Address of the device currently being paired / connected from the list.
    var connectingAddress: String?

    @ObservationIgnored var isDiscovering = false
    /// Whether the device lookup was running when a connect started and should come back after it.
    @ObservationIgnored var resumeAfterConnect = false
    /// The wait between one inquiry and the next; cancelled when discovery stops.
    @ObservationIgnored var inquiryPause: Task<Void, Never>?
    @ObservationIgnored var nearby: [String: any ClassicBluetoothDevice] = [:]
    @ObservationIgnored var nearbyTracker = NearbyTracker()
    @ObservationIgnored var pause = DeviceDiscovery.pauseBetweenInquiries
    @ObservationIgnored var log: (String, OSLogType) -> Void = { logger.log(level: $1, "\($0, privacy: .public)") }
    @ObservationIgnored private let bluetooth: any ClassicBluetooth

    init(bluetooth: any ClassicBluetooth) {
        self.bluetooth = bluetooth
        bluetooth.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    /// Starts looking for nearby Bluetooth devices. Runs until `stop()`.
    func start() {
        // Not while macOS is connecting a device; it resumes when that ends.
        if connectingAddress != nil {
            resumeAfterConnect = true
            return
        }
        guard !isDiscovering else { return }
        isDiscovering = true
        bluetooth.startInquiry()
    }

    func stop() {
        isDiscovering = false
        resumeAfterConnect = false
        inquiryPause?.cancel()
        inquiryPause = nil
        bluetooth.stopInquiry()
    }

    /// Rebuilds the list from paired devices plus anything the inquiry found nearby.
    func refresh() {
        var byAddress = nearby
        for device in bluetooth.pairedDevices() {
            if let address = device.address {
                byAddress[address] = device
            }
        }
        devices = byAddress.values
            .compactMap { device -> JBLDevice? in
                guard let name = device.name, name.localizedCaseInsensitiveContains("JBL"),
                      let address = device.address else { return nil }
                return JBLDevice(name: name, address: address, isConnected: device.isConnected)
            }
            .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
        // macOS may never call back for a device that was already connected, which would leave its
        // row on the gray spinner. Once it is connected there is nothing left to wait for.
        if let address = connectingAddress, devices.contains(where: { $0.address == address && $0.isConnected }) {
            endConnecting()
        }
    }

    /// Pairs (if needed) and connects a device through macOS, so the user doesn't have
    /// to go through System Settings.
    func connect(_ device: JBLDevice) {
        guard let target = bluetooth.device(address: device.address) else { return }
        // The inquiry would compete with the connection for the radio, and the row already shows
        // the progress.
        let wasDiscovering = isDiscovering
        stop()
        resumeAfterConnect = wasDiscovering
        connectingAddress = device.address
        if target.isPaired {
            openConnection(to: device.address)
        } else if !bluetooth.startPairing(address: device.address) {
            log("couldn't start pairing", .error)
            finishConnecting()
        }
    }

    private func openConnection(to address: String) {
        if !bluetooth.openConnection(address: address) {
            log("couldn't connect through macOS", .error)
            finishConnecting()
        }
    }

    /// Clears the pending connect and picks the device lookup back up if it was running.
    private func endConnecting() {
        connectingAddress = nil
        if resumeAfterConnect {
            resumeAfterConnect = false
            start()
        }
    }

    /// Ends a connect attempt, successful or not; the row goes back to its icon for whatever state
    /// macOS reports.
    private func finishConnecting() {
        endConnecting()
        refresh()
    }

    private func handle(_ event: ClassicBluetoothEvent) {
        switch event {
        case let .deviceFound(device):
            if let address = device.address {
                nearby[address] = device
                nearbyTracker.saw(address)
            }
        case let .inquiryCompleted(aborted):
            inquiryCompleted(aborted: aborted)
        case let .pairingFinished(address):
            if let address {
                openConnection(to: address)
            } else {
                log("pairing failed", .error)
                finishConnecting()
            }
        case let .connectionFinished(succeeded):
            if !succeeded {
                log("couldn't connect through macOS", .error)
            }
            finishConnecting()
        }
    }

    private func inquiryCompleted(aborted: Bool) {
        // An inquiry that was stopped early didn't look for everyone, so it says nothing about who left.
        if !aborted {
            for address in nearbyTracker.inquiryCompleted() {
                nearby[address] = nil
            }
            refresh()
        }
        // Keep scanning while the popup is open, after a short pause so the spinner goes away
        // between refreshes.
        guard isDiscovering else { return }
        inquiryPause = Task { [weak self, pause] in
            do { try await Task.sleep(for: pause) } catch { return }
            guard let self, isDiscovering else { return }
            inquiryPause = nil
            bluetooth.startInquiry()
        }
    }
}
