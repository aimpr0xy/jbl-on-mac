extension HeadphoneController {
    /// Starts looking for nearby Bluetooth devices. Runs until `stopDiscovery()`.
    func startDiscovery() {
        // A running classic-Bluetooth inquiry hogs the radio and starves the BLE scan,
        // so only look for devices while the list is showing.
        guard selectedDevice == nil else { return }
        discovery.start()
    }

    func stopDiscovery() {
        discovery.stop()
    }

    /// Rebuilds the list from paired devices plus anything the inquiry found nearby.
    func refreshDevices() {
        discovery.refresh()
    }

    /// Pairs (if needed) and connects a device through macOS.
    func connect(_ device: JBLDevice) {
        discovery.connect(device)
    }
}
