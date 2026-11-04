import Foundation
import IOBluetooth
import os

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

extension HeadphoneController {
    /// How long the list rests between two refreshes.
    static let pauseBetweenInquiries = Duration.seconds(10)

    /// Starts looking for nearby Bluetooth devices. Runs until `stopDiscovery()`.
    func startDiscovery() {
        // A running classic-Bluetooth inquiry hogs the radio and starves the BLE scan,
        // so only look for devices while the list is showing.
        guard selectedDevice == nil else { return }
        // Not while macOS is connecting a device; it resumes when that ends.
        if connectingAddress != nil {
            resumeDiscoveryAfterConnect = true
            return
        }
        guard !isDiscovering else { return }
        isDiscovering = true
        runInquiry()
    }

    func stopDiscovery() {
        isDiscovering = false
        resumeDiscoveryAfterConnect = false
        inquiryPause?.cancel()
        inquiryPause = nil
        inquiry?.stop()
    }

    func runInquiry() {
        let inquiry = inquiry ?? IOBluetoothDeviceInquiry(delegate: self)
        self.inquiry = inquiry
        inquiry?.updateNewDeviceNames = true
        // Otherwise a device found before isn't reported again, and would look like it left.
        inquiry?.clearFoundDevices()
        inquiry?.start()
    }

    /// Rebuilds the list from paired devices plus anything the inquiry found nearby.
    func refreshDevices() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var byAddress: [String: IOBluetoothDevice] = nearby
        for device in paired {
            if let address = device.addressString {
                byAddress[address] = device
            }
        }
        devices = byAddress.values
            .compactMap { device -> JBLDevice? in
                guard let name = device.name, name.localizedCaseInsensitiveContains("JBL"),
                      let address = device.addressString else { return nil }
                return JBLDevice(name: name, address: address, isConnected: device.isConnected())
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
        guard let target = IOBluetoothDevice(addressString: device.address) else { return }
        // The inquiry would compete with the connection for the radio, and the row already shows
        // the progress.
        let wasDiscovering = isDiscovering
        stopDiscovery()
        resumeDiscoveryAfterConnect = wasDiscovering
        connectingAddress = device.address
        if target.isPaired() {
            openConnection(to: target)
        } else {
            let pair = IOBluetoothDevicePair(device: target)
            pairing = pair
            pair?.delegate = self
            if pair?.start() != kIOReturnSuccess {
                log("couldn't start pairing", level: .error)
                finishConnecting()
            }
        }
    }

    func openConnection(to target: IOBluetoothDevice) {
        if target.openConnection(self) != kIOReturnSuccess {
            log("couldn't connect through macOS", level: .error)
            finishConnecting()
        }
    }

    /// Clears the pending connect and picks the device lookup back up if it was running.
    func endConnecting() {
        connectingAddress = nil
        pairing = nil
        if resumeDiscoveryAfterConnect {
            resumeDiscoveryAfterConnect = false
            startDiscovery()
        }
    }

    /// Ends a connect attempt, successful or not; the row goes back to its icon for whatever state
    /// macOS reports.
    func finishConnecting() {
        endConnecting()
        refreshDevices()
    }
}

extension HeadphoneController: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        if let address = device.addressString {
            nearby[address] = device
            nearbyTracker.saw(address)
        }
    }

    func deviceInquiryDeviceNameUpdated(_: IOBluetoothDeviceInquiry!,
                                        device _: IOBluetoothDevice!, devicesRemaining _: UInt32) {
        // The list is rebuilt once the inquiry completes, with the names it found.
    }

    func deviceInquiryComplete(_: IOBluetoothDeviceInquiry!, error _: IOReturn, aborted: Bool) {
        // An inquiry that was stopped early didn't look for everyone, so it says nothing about who left.
        if !aborted {
            for address in nearbyTracker.inquiryCompleted() {
                nearby[address] = nil
            }
            refreshDevices()
        }
        // Keep scanning while the popup is open, after a short pause so the spinner goes away
        // between refreshes.
        guard isDiscovering else { return }
        inquiryPause = Task { [weak self] in
            do { try await Task.sleep(for: Self.pauseBetweenInquiries) } catch { return }
            guard let self, isDiscovering else { return }
            inquiryPause = nil
            runInquiry()
        }
    }
}

extension HeadphoneController: IOBluetoothDevicePairDelegate {
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        guard error == kIOReturnSuccess, let pair = sender as? IOBluetoothDevicePair,
              let device = pair.device() else {
            log("pairing failed", level: .error)
            finishConnecting()
            return
        }
        openConnection(to: device)
    }
}
