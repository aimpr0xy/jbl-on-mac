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
///   ambient sound write      AA 91 07 10 | 01 <NC> | 02 <Ambient> | 03 <TalkThru>   (all 0 = off)
///   level write              AA 91 03 20 | <A1 ambient | 04 noise canceling> <1...7>
///   level query              AA 91 01 21 (assumed from the 10/11/12 pattern)
///   level reply              AA 91 05 22 | 04 <NC> | A1 <Ambient>   (also sent after a change)
///   battery query          AA 06 05 00 01 00 1A 00 1B  (and AA 06 03 00 01 00 1C)
///   battery reply            AA 06 .. 00 02 00 | <id> 02 00 <percent> [00] ...  (1A left, 1B right, 1C case)
///   spatial audio write      AA 06 06 00 00 00 0C 02 01 <Mode>
///   spatial audio query      AA 06 03 00 01 00 0C
///   spatial audio reply      AA 06 06 00 02 00 0C 02 <00|01> <Mode>   (also sent after a change)
///   smart audio/video write  AA 80 09 00 | <8 payload bytes, see SmartAudioMode>
///   smart audio/video query  AA 80 01 01
///   smart audio/video reply  AA 80 09 02 | <8 payload bytes>   (also sent after a change)
///   balance write            AA A8 05 00 01 01 02 <100 + balance>   (0x54 = -16 left ... 0x74 = +16 right)
///   balance query            AA A8 01 01 (assumed from the other features' query pattern)
///   balance reply            AA A8 05 02 01 01 02 <100 + balance>   (also sent after a change)
///   volume limiter write     AA 06 05 00 00 00 20 01 <00 off | 01 on>
///   volume limiter query     AA 06 03 00 01 00 20 (assumed from the spatial audio query pattern)
///   volume limiter reply     AA 06 05 00 02 00 20 01 <00|01>   (also sent after a change)
///   call features write      AA 06 .. 00 00 00 <id> ...   (queries use AA 06 03 00 01 00 <id>, replies AA 06 .. 00 02 00 <id> ...)
///     23  sound level optimizer   AA 06 05 00 00 00 23 01 <00 off | 01 on>
///     14  call sound setting      AA 06 06 00 00 00 14 02 01 <0 natural | 1 treble | 2 bass>
///     16  call voice setting      AA 06 07 00 00 00 16 03 FF FF <0 natural | 1 powerful | 2 bright>
///     0D  voice aware             AA 06 06 00 00 00 0D 02 <00 off | 01 on> <1 low | 2 mid | 3 high>
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
    /// Spatial audio mode reported by the headphones; nil until reported.
    private(set) var selectedSpatialMode: SpatialAudioMode?
    /// Smart audio and video mode reported by the headphones; nil until reported.
    private(set) var selectedSmartMode: SmartAudioMode?
    /// Left / right sound balance (-16 left ... 16 right); nil until reported.
    private(set) var balance: Int?
    /// Whether the max volume limiter is on; nil until reported.
    private(set) var volumeLimiterEnabled: Bool?
    /// Call features reported by the headphones; nil until reported.
    private(set) var soundLevelOptimizerEnabled: Bool?
    private(set) var callSoundSetting: CallSoundSetting?
    private(set) var callVoiceSetting: CallVoiceSetting?
    private(set) var voiceAwareEnabled: Bool?
    private(set) var voiceAwareLevel: VoiceAwareLevel?
    /// Noise canceling and ambient aware strength (1...7); nil until reported.
    private(set) var noiseCancelingLevel: Int?
    private(set) var ambientAwareLevel: Int?
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
        selectedSpatialMode = nil
        selectedSmartMode = nil
        balance = nil
        volumeLimiterEnabled = nil
        noiseCancelingLevel = nil
        ambientAwareLevel = nil
        clearCallFeatures()
        clearBattery()
        startScanning()
    }

    /// Goes back to the device list.
    func deselect() {
        disconnect()
        selectedDevice = nil
        selectedMode = nil
        selectedSpatialMode = nil
        selectedSmartMode = nil
        balance = nil
        volumeLimiterEnabled = nil
        noiseCancelingLevel = nil
        ambientAwareLevel = nil
        clearCallFeatures()
        clearBattery()
        status = .idle
        startDiscovery()
    }

    /// Sends the ambient sound command for the given mode.
    func select(_ mode: ListeningMode) {
        guard let peripheral, let writeCharacteristic else { return }
        // At most one of the three flags is set to 1, matching the app's capture;
        // Off clears all of them.
        let flags: [UInt8] = ListeningMode.flagged.map { $0 == mode ? 1 : 0 }
        let packet = Data([0xAA, 0x91, 0x07, 0x10,
                           0x01, flags[0],
                           0x02, flags[1],
                           0x03, flags[2]])
        peripheral.writeValue(packet, for: writeCharacteristic, type: .withResponse)
        selectedMode = mode
    }

    /// Sets the strength (1...7) of noise canceling or ambient aware.
    func setLevel(_ level: Int, for mode: ListeningMode) {
        guard let peripheral, let writeCharacteristic else { return }
        let level = min(max(level, 1), 7)
        let id: UInt8
        switch mode {
        case .noiseCanceling:
            guard noiseCancelingLevel != level else { return }
            id = 0x04
            noiseCancelingLevel = level
        case .ambientAware:
            guard ambientAwareLevel != level else { return }
            id = 0xA1
            ambientAwareLevel = level
        case .talkThru, .off:
            return
        }
        peripheral.writeValue(Data([0xAA, 0x91, 0x03, 0x20, id, UInt8(level)]),
                              for: writeCharacteristic, type: .withResponse)
    }

    /// Sends the spatial audio command for the given mode.
    func select(_ spatial: SpatialAudioMode) {
        guard let peripheral, let writeCharacteristic else { return }
        let packet = Data([0xAA, 0x06, 0x06, 0x00, 0x00, 0x00, 0x0C, 0x02, 0x01, spatial.rawValue])
        peripheral.writeValue(packet, for: writeCharacteristic, type: .withResponse)
        selectedSpatialMode = spatial
    }

    /// Sends the smart audio and video command for the given mode.
    func select(_ smart: SmartAudioMode) {
        guard let peripheral, let writeCharacteristic else { return }
        let packet = Data([0xAA, 0x80, 0x09, 0x00] + smart.payload)
        peripheral.writeValue(packet, for: writeCharacteristic, type: .withResponse)
        selectedSmartMode = smart
    }

    /// Sets the left / right balance (-16 left ... 16 right).
    func setBalance(_ value: Int) {
        guard let peripheral, let writeCharacteristic else { return }
        let value = min(max(value, -16), 16)
        guard balance != value else { return }
        balance = value
        peripheral.writeValue(Data([0xAA, 0xA8, 0x05, 0x00, 0x01, 0x01, 0x02, UInt8(100 + value)]),
                              for: writeCharacteristic, type: .withResponse)
    }

    /// Turns the max volume limiter on or off.
    func setVolumeLimiter(_ enabled: Bool) {
        guard let peripheral, let writeCharacteristic else { return }
        volumeLimiterEnabled = enabled
        peripheral.writeValue(Data([0xAA, 0x06, 0x05, 0x00, 0x00, 0x00, 0x20, 0x01, enabled ? 1 : 0]),
                              for: writeCharacteristic, type: .withResponse)
    }

    /// Turns the sound level optimizer on or off.
    func setSoundLevelOptimizer(_ enabled: Bool) {
        guard let peripheral, let writeCharacteristic else { return }
        soundLevelOptimizerEnabled = enabled
        peripheral.writeValue(Data([0xAA, 0x06, 0x05, 0x00, 0x00, 0x00, 0x23, 0x01, enabled ? 1 : 0]),
                              for: writeCharacteristic, type: .withResponse)
    }

    /// Sets the sound character used during calls.
    func select(_ setting: CallSoundSetting) {
        guard let peripheral, let writeCharacteristic else { return }
        callSoundSetting = setting
        peripheral.writeValue(Data([0xAA, 0x06, 0x06, 0x00, 0x00, 0x00, 0x14, 0x02, 0x01, setting.rawValue]),
                              for: writeCharacteristic, type: .withResponse)
    }

    /// Sets how your voice sounds to the other side of a call.
    func select(_ setting: CallVoiceSetting) {
        guard let peripheral, let writeCharacteristic else { return }
        callVoiceSetting = setting
        peripheral.writeValue(Data([0xAA, 0x06, 0x07, 0x00, 0x00, 0x00, 0x16, 0x03, 0xFF, 0xFF, setting.rawValue]),
                              for: writeCharacteristic, type: .withResponse)
    }

    /// Turns voice aware on or off, keeping the current level (mid until one is known).
    func setVoiceAware(enabled: Bool) {
        writeVoiceAware(enabled: enabled, level: voiceAwareLevel ?? .mid)
    }

    /// Sets the voice aware level and turns it on.
    func select(_ level: VoiceAwareLevel) {
        writeVoiceAware(enabled: true, level: level)
    }

    private func writeVoiceAware(enabled: Bool, level: VoiceAwareLevel) {
        guard let peripheral, let writeCharacteristic else { return }
        voiceAwareEnabled = enabled
        voiceAwareLevel = level
        peripheral.writeValue(Data([0xAA, 0x06, 0x06, 0x00, 0x00, 0x00, 0x0D, 0x02, enabled ? 1 : 0, level.rawValue]),
                              for: writeCharacteristic, type: .withResponse)
    }

    private func clearCallFeatures() {
        soundLevelOptimizerEnabled = nil
        callSoundSetting = nil
        callVoiceSetting = nil
        voiceAwareEnabled = nil
        voiceAwareLevel = nil
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
        log.notice("didFailToConnect error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public)")
        failedAttempts += 1
        retryConnecting()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log.notice("didDisconnect error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public) expected=\(self.expectedDisconnects.contains(peripheral.identifier))")
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
        peripheral.writeValue(Data([0xAA, 0x91, 0x01, 0x21]), for: writeCharacteristic, type: .withResponse)
        // Ask for the left / right earbud and case battery levels.
        peripheral.writeValue(Data([0xAA, 0x06, 0x05, 0x00, 0x01, 0x00, 0x1A, 0x00, 0x1B]),
                              for: writeCharacteristic, type: .withResponse)
        peripheral.writeValue(Data([0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, 0x1C]),
                              for: writeCharacteristic, type: .withResponse)
        // And which smart audio and video mode is active.
        peripheral.writeValue(Data([0xAA, 0x80, 0x01, 0x01]), for: writeCharacteristic, type: .withResponse)
        // And which spatial audio mode is active.
        peripheral.writeValue(Data([0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, 0x0C]),
                              for: writeCharacteristic, type: .withResponse)
        // And the left / right balance.
        peripheral.writeValue(Data([0xAA, 0xA8, 0x01, 0x01]), for: writeCharacteristic, type: .withResponse)
        // And whether the max volume limiter is on.
        peripheral.writeValue(Data([0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, 0x20]),
                              for: writeCharacteristic, type: .withResponse)
        // And the call features: optimizer, sound setting, voice setting, voice aware.
        for id: UInt8 in [0x23, 0x14, 0x16, 0x0D] {
            peripheral.writeValue(Data([0xAA, 0x06, 0x03, 0x00, 0x01, 0x00, id]),
                                  for: writeCharacteristic, type: .withResponse)
        }
    }

    /// Call feature replies are `AA 06 <len> 00 02 00 <id> ...`; see the protocol notes at the top.
    private func parseCallFeatures(_ bytes: [UInt8]) {
        guard bytes.count >= 9, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02 else { return }
        switch bytes[6] {
        case 0x23 where bytes[8] <= 1:
            soundLevelOptimizerEnabled = bytes[8] == 1
        case 0x14 where bytes.count >= 10:
            callSoundSetting = CallSoundSetting(rawValue: bytes[9])
        case 0x16 where bytes.count >= 11:
            callVoiceSetting = CallVoiceSetting(rawValue: bytes[10])
        case 0x0D where bytes.count >= 10 && bytes[8] <= 1:
            voiceAwareEnabled = bytes[8] == 1
            voiceAwareLevel = VoiceAwareLevel(rawValue: bytes[9])
        default: break
        }
    }

    /// Volume limiter replies are `AA 06 05 00 02 00 20 01 <00|01>`.
    private func parseVolumeLimiter(_ bytes: [UInt8]) {
        guard bytes.count >= 9, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02,
              bytes[6] == 0x20, bytes[7] == 0x01, bytes[8] <= 1 else { return }
        volumeLimiterEnabled = bytes[8] == 1
    }

    /// Balance replies are `AA A8 05 02 01 <enabled> 02 <100 + balance>`.
    private func parseBalance(_ bytes: [UInt8]) {
        guard bytes.count >= 8, bytes[0] == 0xAA, bytes[1] == 0xA8, bytes[3] == 0x02,
              bytes[6] == 0x02, (84...116).contains(Int(bytes[7])) else { return }
        balance = Int(bytes[7]) - 100
    }

    /// Level replies are `AA 91 05 22` followed by `<id> <level>` pairs (04 = noise canceling,
    /// A1 = ambient aware). The mode report `AA 91 09 12 ... 04 <level>` also carries the NC level.
    private func parseLevels(_ bytes: [UInt8]) {
        guard bytes.count >= 6, bytes[0] == 0xAA, bytes[1] == 0x91 else { return }
        var index: Int
        switch bytes[3] {
        case 0x22: index = 4
        case 0x12: index = 10
        default: return
        }
        while index + 1 < bytes.count {
            let level = Int(bytes[index + 1])
            if (1...7).contains(level) {
                if bytes[index] == 0x04 { noiseCancelingLevel = level }
                if bytes[index] == 0xA1 { ambientAwareLevel = level }
            }
            index += 2
        }
    }

    /// Spatial audio replies are `AA 06 06 00 02 00 0C 02 <00|01> <mode>`.
    private func parseSpatialAudio(_ bytes: [UInt8]) {
        guard bytes.count >= 10, bytes[0] == 0xAA, bytes[1] == 0x06, bytes[4] == 0x02,
              bytes[6] == 0x0C, let mode = SpatialAudioMode(rawValue: bytes[9]) else { return }
        selectedSpatialMode = mode
    }

    /// Smart audio and video replies are `AA 80 09 02` followed by the 8 payload bytes.
    private func parseSmartAudio(_ bytes: [UInt8]) {
        guard bytes.count >= 12, bytes[0] == 0xAA, bytes[1] == 0x80, bytes[2] == 0x09,
              bytes[3] == 0x02, let mode = SmartAudioMode(payload: Array(bytes[4..<12])) else { return }
        selectedSmartMode = mode
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
        parseSpatialAudio(bytes)
        parseSmartAudio(bytes)
        parseBalance(bytes)
        parseVolumeLimiter(bytes)
        parseCallFeatures(bytes)
        parseLevels(bytes)
        guard bytes.count >= 10, bytes[0] == 0xAA, bytes[1] == 0x91, bytes[3] == 0x12 else { return }
        let flags = [bytes[5], bytes[7], bytes[9]]
        // All flags cleared means ambient sound control is off.
        selectedMode = flags.firstIndex(of: 1).map { ListeningMode.flagged[$0] } ?? .off
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
