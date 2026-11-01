import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

private let log = Logger(subsystem: "JblOnMac", category: "BLE")

/// A JBL product that is either nearby, paired, or connected over Bluetooth.
struct JBLDevice: Identifiable, Hashable {
    let name: String
    let address: String
    let isConnected: Bool
    var id: String { address }
}

/// Discovers nearby JBL products, connects them through macOS Bluetooth, and talks to the
/// selected one over BLE using the protocol observed in the Packet Logger capture of the JBL app:
///   service characteristics  ...6F6D0002 (write)  /  ...6F6D0001 (notify)
///   ambient sound write      AA 91 07 10 | 01 <NC> | 02 <Ambient> | 03 <TalkThru>
///   battery query            AA 06 05 00 01 00 1A 00 1B  (and AA 06 03 00 01 00 1C)
///   battery reply            AA 06 .. 00 02 00 | <id> 02 00 <percent> [00] ...  (1A left, 1B right, 1C case)
@Observable
final class HeadphoneController: NSObject {
    enum Status: Equatable {
        case idle
        case bluetoothOff
        case unauthorized
        case scanning
        case connecting
        case connected
    }

    private(set) var devices: [JBLDevice] = []
    private(set) var selectedDevice: JBLDevice?
    private(set) var status: Status = .idle
    private(set) var selectedMode: ListeningMode?
    /// Battery percentages reported by the headphones; nil until reported.
    private(set) var leftBattery: Int?
    private(set) var rightBattery: Int?
    private(set) var caseBattery: Int?
    /// Address of the device currently being paired / connected from the list.
    private(set) var connectingAddress: String?
    private(set) var connectionError: String?

    private let writeUUID = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0002")
    private let notifyUUID = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0001")

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?

    @ObservationIgnored private var inquiry: IOBluetoothDeviceInquiry?
    @ObservationIgnored private var isDiscovering = false
    @ObservationIgnored private var nearby: [String: IOBluetoothDevice] = [:]
    @ObservationIgnored private var pairing: IOBluetoothDevicePair?

    /// Core Bluetooth identifier of the headphones' LE link, remembered after a successful
    /// connection. Seeded with the identifier seen for the "JBL Tune Beam 2" on this Mac.
    @ObservationIgnored private var failedAttempts = 0
    @ObservationIgnored private var connectAttempt = 0
    /// Links we cancelled ourselves, so their late disconnect callback doesn't trigger a retry
    /// that would tear down the fresh attempt.
    @ObservationIgnored private var expectedDisconnects: Set<UUID> = []
    @ObservationIgnored private var rememberedIdentifier: UUID? {
        get {
            let stored = UserDefaults.standard.string(forKey: "lePeripheralIdentifier")
                ?? "4E7D3055-217E-77DB-AE69-E20CA1B97517"
            return UUID(uuidString: stored)
        }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "lePeripheralIdentifier") }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        // Release the headphones' single LE link cleanly on quit, so the next launch
        // doesn't have to wait for the stale connection to time out.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.disconnect() }
        }
    }

    // MARK: - Discovery and connecting through macOS Bluetooth

    /// Starts looking for nearby Bluetooth devices. Runs until `stopDiscovery()`.
    func startDiscovery() {
        // A running classic-Bluetooth inquiry hogs the radio and starves the BLE scan,
        // so only look for devices while the list is showing.
        guard !isDiscovering, selectedDevice == nil else { return }
        isDiscovering = true
        runInquiry()
    }

    func stopDiscovery() {
        isDiscovering = false
        inquiry?.stop()
    }

    private func runInquiry() {
        let inquiry = inquiry ?? IOBluetoothDeviceInquiry(delegate: self)
        self.inquiry = inquiry
        inquiry?.inquiryLength = 6
        inquiry?.updateNewDeviceNames = true
        inquiry?.start()
    }

    /// Rebuilds the list from paired devices plus anything the inquiry found nearby.
    func refreshDevices() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var byAddress: [String: IOBluetoothDevice] = nearby
        for device in paired {
            if let address = device.addressString { byAddress[address] = device }
        }
        devices = byAddress.values
            .compactMap { device -> JBLDevice? in
                guard let name = device.name, name.localizedCaseInsensitiveContains("JBL"),
                      let address = device.addressString else { return nil }
                return JBLDevice(name: name, address: address, isConnected: device.isConnected())
            }
            .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
    }

    /// Pairs (if needed) and connects a device through macOS, so the user doesn't have
    /// to go through System Settings.
    func connect(_ device: JBLDevice) {
        guard let target = IOBluetoothDevice(addressString: device.address) else { return }
        connectionError = nil
        connectingAddress = device.address
        if target.isPaired() {
            openConnection(to: target)
        } else {
            let pair = IOBluetoothDevicePair(device: target)
            pairing = pair
            pair?.delegate = self
            if pair?.start() != kIOReturnSuccess {
                finishConnecting(error: "Couldn't start pairing")
            }
        }
    }

    private func openConnection(to target: IOBluetoothDevice) {
        if target.openConnection(self) != kIOReturnSuccess {
            finishConnecting(error: "Couldn't connect")
        }
    }

    private func finishConnecting(error: String?) {
        connectingAddress = nil
        pairing = nil
        connectionError = error
        refreshDevices()
    }

    // MARK: - Selecting a device and controlling it over BLE

    /// Picks a connected headphone and opens its BLE link so its controls can be shown.
    func select(_ device: JBLDevice) {
        disconnect()
        stopDiscovery()
        selectedDevice = device
        selectedMode = nil
        clearBattery()
        startScanning()
    }

    /// Goes back to the device list.
    func deselect() {
        disconnect()
        selectedDevice = nil
        selectedMode = nil
        clearBattery()
        status = .idle
        startDiscovery()
    }

    /// Sends the ambient sound command for the given mode.
    func select(_ mode: ListeningMode) {
        guard let peripheral, let writeCharacteristic else { return }
        // Exactly one of the three flags is set to 1, matching the app's capture.
        let flags: [UInt8] = ListeningMode.allCases.map { $0 == mode ? 1 : 0 }
        let packet = Data([0xAA, 0x91, 0x07, 0x10,
                           0x01, flags[0],
                           0x02, flags[1],
                           0x03, flags[2]])
        peripheral.writeValue(packet, for: writeCharacteristic, type: .withResponse)
        selectedMode = mode
    }

    private func clearBattery() {
        leftBattery = nil
        rightBattery = nil
        caseBattery = nil
    }

    private func startScanning() {
        log.notice("authorization=\(CBCentralManager.authorization.rawValue) state=\(self.central.state.rawValue)")
        guard CBCentralManager.authorization == .allowedAlways else {
            status = .unauthorized
            return
        }
        guard central.state == .poweredOn else {
            status = central.state == .unauthorized ? .unauthorized : .bluetoothOff
            return
        }
        status = .scanning
        // Scanning doesn't deliver any results on some Macs, but connecting to a peripheral
        // by its remembered identifier does work, so keep retrying that.
        if let id = rememberedIdentifier,
           let match = central.retrievePeripherals(withIdentifiers: [id]).first {
            log.notice("connecting to remembered peripheral \(id.uuidString, privacy: .public)")
            // The identifier may be stale (the headphones can change their LE address),
            // so after a couple of failures also scan for a new one.
            if failedAttempts >= 2 { central.scanForPeripherals(withServices: nil) }
            connectToHeadphones(match)
            return
        }
        // The headphones may already hold a BLE link to the system (e.g. via the audio
        // connection), in which case they don't advertise and a scan would never find them.
        let alreadyConnected = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "1800")])
        log.notice("already connected: \(alreadyConnected.map { $0.name ?? "nil" }, privacy: .public), target=\(self.selectedDevice?.name ?? "nil", privacy: .public), state=\(self.central.state.rawValue)")
        if let match = alreadyConnected.first(where: { matchesSelectedDevice(name: $0.name) }) {
            connectToHeadphones(match)
            return
        }
        armWatchdog()
        central.scanForPeripherals(withServices: nil)
    }

    /// The BLE name can differ slightly from the classic Bluetooth name, so fall back to any JBL.
    private func matchesSelectedDevice(name: String?) -> Bool {
        guard let name, let target = selectedDevice else { return false }
        return name.caseInsensitiveCompare(target.name) == .orderedSame
            || name.localizedCaseInsensitiveContains("JBL")
    }

    private func connectToHeadphones(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        status = .connecting
        if peripheral.state == .connected {
            peripheral.discoverServices(nil)
        } else {
            central.connect(peripheral)
        }
        armWatchdog()
    }

    /// Any attempt can hang forever (stale identifier, headphones still busy with another link,
    /// a scan that never delivers a result, services that never show up), so if we're not
    /// connected after a while, tear everything down and start over.
    private func armWatchdog() {
        connectAttempt += 1
        let attempt = connectAttempt
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.connectAttempt == attempt, self.status != .connected,
                  self.selectedDevice != nil else { return }
            log.notice("watchdog: attempt timed out, restarting")
            self.failedAttempts += 1
            self.disconnect()
            self.startScanning()
        }
    }

    private func disconnect() {
        central.stopScan()
        if let peripheral {
            expectedDisconnects.insert(peripheral.identifier)
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        writeCharacteristic = nil
    }

    /// Delegate callback for `IOBluetoothDevice.openConnection(_:)`.
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        finishConnecting(error: status == kIOReturnSuccess ? nil : "Couldn't connect")
    }
}

extension HeadphoneController: @preconcurrency IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        if let address = device.addressString { nearby[address] = device }
        refreshDevices()
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!,
                                        device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        refreshDevices()
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        // Keep scanning while the popup is open.
        if isDiscovering { runInquiry() }
    }
}

extension HeadphoneController: @preconcurrency IOBluetoothDevicePairDelegate {
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        guard error == kIOReturnSuccess, let pair = sender as? IOBluetoothDevicePair,
              let device = pair.device() else {
            finishConnecting(error: "Pairing failed. Put the headphones in pairing mode and try again.")
            return
        }
        openConnection(to: device)
    }
}

extension HeadphoneController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.notice("didUpdateState \(central.state.rawValue)")
        if central.state == .poweredOn {
            if selectedDevice != nil { startScanning() }
        } else if selectedDevice != nil {
            status = central.state == .unauthorized ? .unauthorized : .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        log.notice("discovered name=\(name ?? "nil", privacy: .public) rssi=\(RSSI.intValue) adv=\(String(describing: advertisementData), privacy: .public)")
        guard matchesSelectedDevice(name: name) else { return }
        central.stopScan()
        connectToHeadphones(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        rememberedIdentifier = peripheral.identifier
        expectedDisconnects.remove(peripheral.identifier)
        failedAttempts = 0
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        failedAttempts += 1
        retryConnecting()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if expectedDisconnects.remove(peripheral.identifier) != nil { return }
        // Ignore the late callback for a link we already replaced with a new attempt.
        if let current = self.peripheral, current !== peripheral { return }
        writeCharacteristic = nil
        self.peripheral = nil
        retryConnecting()
    }

    /// Tries again shortly after a failure or a dropped link, as long as a device is selected.
    private func retryConnecting() {
        guard selectedDevice != nil else { return }
        status = .connecting
        connectAttempt += 1
        let attempt = connectAttempt
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.connectAttempt == attempt, self.selectedDevice != nil,
                  self.peripheral == nil else { return }
            self.startScanning()
        }
    }
}

extension HeadphoneController: @preconcurrency CBPeripheralDelegate {
    /// Once notifications are on, ask the headphones which ambient sound mode is active.
    /// The JBL app does the same with `AA 91 01 11`.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyUUID, characteristic.isNotifying,
              let writeCharacteristic else { return }
        peripheral.writeValue(Data([0xAA, 0x91, 0x01, 0x11]), for: writeCharacteristic, type: .withResponse)
        // Ask for the left / right earbud and case battery levels.
        peripheral.writeValue(Data([0xAA, 0x06, 0x05, 0x00, 0x01, 0x00, 0x1A, 0x00, 0x1B]),
                              for: writeCharacteristic, type: .withResponse)
        peripheral.writeValue(Data([0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, 0x1C]),
                              for: writeCharacteristic, type: .withResponse)
    }

    /// Battery replies (and later unsolicited updates) are `AA 06 <len> 00 02 00` followed by
    /// entries of `<id> 02 00 <percent>`, optionally separated by a `00` byte.
    private func parseBattery(_ bytes: [UInt8]) {
        guard bytes.count >= 10, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02 else { return }
        var index = 6
        while index + 3 < bytes.count {
            let percent = Int(bytes[index + 3])
            if percent <= 100 {
                switch bytes[index] {
                case 0x1A: leftBattery = percent
                case 0x1B: rightBattery = percent
                case 0x1C: caseBattery = percent
                default: break
                }
            }
            index += 4
            if index < bytes.count, bytes[index] == 0 { index += 1 }
        }
    }

    /// The headphones report the active mode as `AA 91 09 12 01 <NC> 02 <Ambient> 03 <TalkThru> 04 07`,
    /// both when asked and after a change.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyUUID, let bytes = characteristic.value.map([UInt8].init) else { return }
        parseBattery(bytes)
        guard bytes.count >= 10, bytes[0] == 0xAA, bytes[1] == 0x91, bytes[3] == 0x12 else { return }
        let flags = [bytes[5], bytes[7], bytes[9]]
        guard let index = flags.firstIndex(of: 1) else { return }
        selectedMode = ListeningMode.allCases[index]
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == notifyUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == writeUUID {
                writeCharacteristic = characteristic
                status = .connected
            }
        }
    }
}
