import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

let log = Logger(subsystem: "JblOnMac", category: "BLE")

/// Discovers nearby JBL products, connects them through macOS Bluetooth, and talks to the
/// selected one over BLE. Packets are built by `JBLCommand` and decoded by `JBLReply`.
@MainActor
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

    var devices: [JBLDevice] = []
    var selectedDevice: JBLDevice?
    var status: Status = .idle
    /// Whether the Mac's Bluetooth radio is switched off. Tracked separately from `status`,
    /// which only reflects Bluetooth while a device is selected.
    var isBluetoothOff = false
    /// Values reported by the selected headphones; reset as a whole when the selection changes.
    var state = DeviceState()
    /// Address of the device currently being paired / connected from the list.
    var connectingAddress: String?
    var connectionError: LocalizedStringResource?

    let writeUUID = JBLUUID.write
    let notifyUUID = JBLUUID.notify

    @ObservationIgnored var central: CBCentralManager!
    @ObservationIgnored var peripheral: CBPeripheral?
    @ObservationIgnored var writeCharacteristic: CBCharacteristic?
    /// Commands written but not yet acknowledged, oldest first; write-with-response results
    /// arrive in order, and the callback doesn't say which command it is for.
    @ObservationIgnored var pendingWrites: [JBLCommand] = []

    @ObservationIgnored var inquiry: IOBluetoothDeviceInquiry?
    @ObservationIgnored var isDiscovering = false
    @ObservationIgnored var nearby: [String: IOBluetoothDevice] = [:]
    @ObservationIgnored var pairing: IOBluetoothDevicePair?

    /// A discovered JBL whose name isn't an exact match; used only if no exact match
    /// turns up shortly after.
    @ObservationIgnored var fallbackPeripheral: CBPeripheral?
    /// Failed attempts since the last successful connection; drives the retry backoff.
    @ObservationIgnored var failedAttempts = 0
    /// After this many failed attempts in a row, stop retrying and show an error.
    let maxFailedAttempts = 5
    @ObservationIgnored var connectAttempt = 0
    /// Links we cancelled ourselves, so their late disconnect callback doesn't trigger a retry
    /// that would tear down the fresh attempt.
    @ObservationIgnored var expectedDisconnects: Set<UUID> = []
    /// Peripherals whose connection we cancelled, kept alive until Core Bluetooth reports the
    /// disconnect. Dropping the last reference while a link is still connecting makes Core
    /// Bluetooth log "API MISUSE: Cancelling connection for unused peripheral".
    @ObservationIgnored var cancelling: [UUID: CBPeripheral] = [:]
    /// Core Bluetooth identifier of the headphones' LE link, remembered after a successful
    /// connection. Stored per device (by classic Bluetooth address), so each pair of headphones
    /// remembers its own LE link. Nil until a connection succeeds, or when no device is selected.
    @ObservationIgnored var rememberedIdentifier: UUID? {
        get {
            guard let key = rememberedIdentifierKey else { return nil }
            // Before identifiers were stored per device there was a single global one; keep using
            // it until the next successful connection moves it to the per-device key.
            guard let stored = UserDefaults.standard.string(forKey: key)
                    ?? UserDefaults.standard.string(forKey: Self.legacyIdentifierKey) else { return nil }
            return UUID(uuidString: stored)
        }
        set {
            guard let key = rememberedIdentifierKey else { return }
            UserDefaults.standard.set(newValue?.uuidString, forKey: key)
            UserDefaults.standard.removeObject(forKey: Self.legacyIdentifierKey)
        }
    }

    private static let legacyIdentifierKey = "lePeripheralIdentifier"

    private var rememberedIdentifierKey: String? {
        selectedDevice.map { "lePeripheralIdentifier.\($0.address)" }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        // Release the headphones' single LE link cleanly on quit, so the next launch
        // doesn't have to wait for the stale connection to time out. This stays a synchronous
        // observer (an async sequence might not run before the app exits). It is delivered on
        // the main queue, so `assumeIsolated` only asserts what `queue: .main` already guarantees.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.disconnect() }
        }
        selectLastDeviceIfConnected()
    }

    // MARK: - Remembering the last device

    private static let lastDeviceKey = "lastDevice"

    /// Name and classic Bluetooth address of the last device that connected successfully.
    private var lastDevice: (name: String, address: String)? {
        get {
            guard let stored = UserDefaults.standard.dictionary(forKey: Self.lastDeviceKey) as? [String: String],
                  let name = stored["name"], let address = stored["address"] else { return nil }
            return (name, address)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(["name": newValue.name, "address": newValue.address],
                                          forKey: Self.lastDeviceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastDeviceKey)
            }
        }
    }

    /// Records the selected device as the one to reopen on the next launch.
    func rememberSelectedDevice() {
        guard let device = selectedDevice else { return }
        lastDevice = (device.name, device.address)
    }

    /// On launch, reopens the last used headphones if macOS still has them connected. Headphones
    /// that are off or away are left alone, so the app doesn't retry a link that can't succeed.
    private func selectLastDeviceIfConnected() {
        guard let last = lastDevice,
              let target = IOBluetoothDevice(addressString: last.address),
              target.isPaired(), target.isConnected() else { return }
        select(JBLDevice(name: last.name, address: last.address, isConnected: true))
    }

    // MARK: - Selecting a device and controlling it over BLE

    /// Picks a connected headphone and opens its BLE link so its controls can be shown.
    func select(_ device: JBLDevice) {
        disconnect()
        stopDiscovery()
        failedAttempts = 0
        connectionError = nil
        selectedDevice = device
        state = DeviceState()
        startScanning()
    }

    /// Goes back to the device list. By default this also forgets the last device, so it isn't
    /// reopened on the next launch; failed connection attempts keep it.
    func deselect(forgetLastDevice: Bool = true) {
        if forgetLastDevice { lastDevice = nil }
        disconnect()
        selectedDevice = nil
        state = DeviceState()
        status = .idle
        startDiscovery()
    }

    /// Writes a command to the headphones; does nothing until the BLE link is ready.
    func send(_ command: JBLCommand) {
        guard let peripheral, let writeCharacteristic else { return }
        pendingWrites.append(command)
        peripheral.writeValue(Data(command.bytes), for: writeCharacteristic, type: .withResponse)
    }

    /// Called when the headphones confirm or reject the oldest outstanding write. The UI is
    /// updated optimistically, so a failed write must be undone: ask the headphones for the real
    /// state, or forget the value when there's no query for it.
    func writeCompleted(error: Error?) {
        guard !pendingWrites.isEmpty else { return }
        let command = pendingWrites.removeFirst()
        guard let error else { return }
        log.error("write failed for \(String(describing: command), privacy: .public): \(error.localizedDescription, privacy: .public)")
        if let query = command.refreshQuery {
            send(query)
        } else if case .setEqualizer = command {
            state.equalizer = nil
        }
    }

    /// Whether the BLE link is ready for writes.
    private var canSend: Bool { peripheral != nil && writeCharacteristic != nil }

    /// Sends the ambient sound command for the given mode.
    func select(_ mode: ListeningMode) {
        guard canSend else { return }
        send(.setListeningMode(mode))
        state.mode = mode
    }

    /// Sets the strength (1...7) of noise canceling or ambient aware.
    func setLevel(_ level: Int, for mode: ListeningMode) {
        guard canSend else { return }
        let level = min(max(level, 1), 7)
        switch mode {
        case .noiseCanceling:
            guard state.noiseCancelingLevel != level else { return }
            state.noiseCancelingLevel = level
        case .ambientAware:
            guard state.ambientAwareLevel != level else { return }
            state.ambientAwareLevel = level
        case .talkThru, .off:
            return
        }
        send(.setLevel(mode, level))
    }

    /// Sends the spatial audio command for the given mode.
    func select(_ spatial: SpatialAudioMode) {
        guard canSend else { return }
        send(.setSpatialAudio(spatial))
        state.spatialMode = spatial
    }

    /// Sends the smart audio and video command for the given mode.
    func select(_ smart: SmartAudioMode) {
        guard canSend else { return }
        send(.setSmartAudio(smart))
        state.smartMode = smart
    }

    /// Sets the left / right balance (-16 left ... 16 right).
    func setBalance(_ value: Int) {
        guard canSend else { return }
        let value = min(max(value, -16), 16)
        guard state.balance != value else { return }
        state.balance = value
        send(.setBalance(value))
    }

    /// Sends the equalizer command for the given preset.
    func select(_ preset: EqualizerPreset) {
        guard canSend else { return }
        send(.setEqualizer(preset))
        state.equalizer = preset
    }

    /// Turns the max volume limiter on or off.
    func setVolumeLimiter(_ enabled: Bool) {
        guard canSend else { return }
        state.volumeLimiterEnabled = enabled
        send(.setVolumeLimiter(enabled))
    }

    /// Turns the sound level optimizer on or off.
    func setSoundLevelOptimizer(_ enabled: Bool) {
        guard canSend else { return }
        state.soundLevelOptimizerEnabled = enabled
        send(.setSoundLevelOptimizer(enabled))
    }

    /// Sets the sound character used during calls.
    func select(_ setting: CallSoundSetting) {
        guard canSend else { return }
        state.callSoundSetting = setting
        send(.setCallSound(setting))
    }

    /// Sets how your voice sounds to the other side of a call.
    func select(_ setting: CallVoiceSetting) {
        guard canSend else { return }
        state.callVoiceSetting = setting
        send(.setCallVoice(setting))
    }

    /// Turns voice aware on or off, keeping the current level (mid until one is known).
    func setVoiceAware(enabled: Bool) {
        writeVoiceAware(enabled: enabled, level: state.voiceAwareLevel ?? .mid)
    }

    /// Sets the voice aware level and turns it on.
    func select(_ level: VoiceAwareLevel) {
        writeVoiceAware(enabled: true, level: level)
    }

    func writeVoiceAware(enabled: Bool, level: VoiceAwareLevel) {
        guard canSend else { return }
        state.voiceAwareEnabled = enabled
        state.voiceAwareLevel = level
        send(.setVoiceAware(enabled: enabled, level: level))
    }

    func startScanning() {
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
        if let match = alreadyConnected.first(where: { matchesSelectedDeviceExactly(name: $0.name) })
            ?? alreadyConnected.first(where: { matchesSelectedDevice(name: $0.name) }) {
            connectToHeadphones(match)
            return
        }
        armWatchdog()
        central.scanForPeripherals(withServices: nil)
    }

    /// Whether a BLE name is the same as the selected device's classic Bluetooth name. The LE side
    /// advertises that name with an "-LE" suffix (e.g. "JBL Tune Beam 2-LE"), which still counts.
    func matchesSelectedDeviceExactly(name: String?) -> Bool {
        guard let name, let target = selectedDevice else { return false }
        return name.caseInsensitiveCompare(target.name) == .orderedSame
            || name.caseInsensitiveCompare(target.name + "-LE") == .orderedSame
    }

    /// The BLE name can differ slightly from the classic Bluetooth name, so any JBL is a
    /// fallback. Callers should prefer `matchesSelectedDeviceExactly` and only use this when
    /// no exact match shows up, so a nearby JBL speaker isn't picked over the headphones.
    func matchesSelectedDevice(name: String?) -> Bool {
        guard let name, selectedDevice != nil else { return false }
        return matchesSelectedDeviceExactly(name: name)
            || name.localizedCaseInsensitiveContains("JBL")
    }

    func connectToHeadphones(_ peripheral: CBPeripheral) {
        // A previous attempt may still be connecting (e.g. the remembered identifier was stale and
        // a scan found the headphones under a new one); cancel it instead of just dropping it.
        if let previous = self.peripheral, previous.identifier != peripheral.identifier {
            cancelConnection(previous)
        }
        self.peripheral = peripheral
        peripheral.delegate = self
        status = .connecting
        log.notice("connectToHeadphones state=\(peripheral.state.rawValue) name=\(peripheral.name ?? "nil", privacy: .public)")
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
    func armWatchdog() {
        connectAttempt += 1
        let attempt = connectAttempt
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.connectAttempt == attempt, self.status != .connected,
                  self.selectedDevice != nil else { return }
            log.notice("watchdog: attempt timed out")
            self.failedAttempts += 1
            self.disconnect()
            self.retryConnecting()
        }
    }

    /// Stops retrying and goes back to the device list with an error, so the app doesn't keep
    /// the radio busy forever when the headphones are off or out of range.
    func giveUpConnecting() {
        let name = selectedDevice?.name ?? String(localized: "the headphones")
        log.notice("giving up after \(self.failedAttempts) failed attempts")
        deselect(forgetLastDevice: false)
        connectionError = LocalizedStringResource("Couldn't reach \(name). Make sure it's turned on and nearby, then try again.")
    }

    func disconnect() {
        central.stopScan()
        fallbackPeripheral = nil
        if let peripheral { cancelConnection(peripheral) }
        peripheral = nil
        writeCharacteristic = nil
        pendingWrites.removeAll()
    }

    /// Cancels a link on purpose and keeps the peripheral alive until the cancel completes.
    func cancelConnection(_ peripheral: CBPeripheral) {
        expectedDisconnects.insert(peripheral.identifier)
        cancelling[peripheral.identifier] = peripheral
        central.cancelPeripheralConnection(peripheral)
    }

    /// Delegate callback for `IOBluetoothDevice.openConnection(_:)`.
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        finishConnecting(error: status == kIOReturnSuccess ? nil : "Couldn't connect")
    }
}
