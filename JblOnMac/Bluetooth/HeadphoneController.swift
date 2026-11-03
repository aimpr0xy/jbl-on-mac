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

        init(_ phase: ConnectionStateMachine.Phase) {
            switch phase {
            case .idle: self = .idle
            case .scanning: self = .scanning
            case .connecting: self = .connecting
            case .connected: self = .connected
            }
        }
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

    /// Decides when to connect, retry, time out and give up; this class carries out its actions.
    @ObservationIgnored var machine = ConnectionStateMachine()
    /// Peripherals seen this session, by identifier, so the machine's actions can refer to them.
    @ObservationIgnored var known: [UUID: CBPeripheral] = [:]
    @ObservationIgnored var timers: [ConnectionStateMachine.Timer: Task<Void, Never>] = [:]
    /// Links we cancelled ourselves, so their late disconnect callback isn't mistaken for a drop
    /// of a fresh attempt that reuses the same identifier.
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
        connectionError = nil
        selectedDevice = device
        state = DeviceState()
        handle(.selected)
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
        // Scanning doesn't deliver any results on some Macs, but connecting to a peripheral
        // by its remembered identifier does work, so keep retrying that.
        if let id = rememberedIdentifier,
           let match = central.retrievePeripherals(withIdentifiers: [id]).first {
            log.notice("connecting to remembered peripheral \(id.uuidString, privacy: .public)")
            known[id] = match
            handle(.attempt(.remembered(id)))
            return
        }
        // The headphones may already hold a BLE link to the system (e.g. via the audio
        // connection), in which case they don't advertise and a scan would never find them.
        let alreadyConnected = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "1800")])
        log.notice("already connected: \(alreadyConnected.map { $0.name ?? "nil" }, privacy: .public), target=\(self.selectedDevice?.name ?? "nil", privacy: .public), state=\(self.central.state.rawValue)")
        if let match = alreadyConnected.first(where: { matchesSelectedDeviceExactly(name: $0.name) })
            ?? alreadyConnected.first(where: { matchesSelectedDevice(name: $0.name) }) {
            known[match.identifier] = match
            handle(.attempt(.alreadyConnected(match.identifier)))
            return
        }
        handle(.attempt(.none))
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

    /// How well a BLE name matches the selected device.
    func nameMatch(for name: String?) -> ConnectionStateMachine.NameMatch {
        if matchesSelectedDeviceExactly(name: name) { return .exact }
        return matchesSelectedDevice(name: name) ? .fallback : .none
    }

    // MARK: - Running the connection state machine

    /// Feeds an event to the state machine and carries out what it asks for.
    func handle(_ event: ConnectionStateMachine.Event) {
        let phase = machine.phase
        let actions = machine.handle(event)
        log.debug("\(String(describing: event), privacy: .public) -> \(String(describing: actions), privacy: .public)")
        if machine.phase != phase { status = Status(machine.phase) }
        for action in actions { perform(action) }
        // The machine dropped the link (failure, disconnect, timeout or deselect).
        if machine.current == nil {
            peripheral = nil
            writeCharacteristic = nil
            pendingWrites.removeAll()
        }
    }

    private func perform(_ action: ConnectionStateMachine.Action) {
        switch action {
        case .beginAttempt:
            startScanning()
        case .connect(let id):
            guard let target = known[id] else { return }
            if peripheral?.identifier != id {
                writeCharacteristic = nil
                pendingWrites.removeAll()
            }
            peripheral = target
            target.delegate = self
            log.notice("connecting state=\(target.state.rawValue) name=\(target.name ?? "nil", privacy: .public)")
            if target.state == .connected {
                target.discoverServices(nil)
            } else {
                central.connect(target)
            }
        case .scan:
            central.scanForPeripherals(withServices: nil)
        case .stopScan:
            central.stopScan()
        case .cancel(let id):
            if let target = known[id] { cancelConnection(target) }
        case .discoverServices(let id):
            known[id]?.discoverServices(nil)
        case .startTimer(let timer, let duration):
            timers[timer]?.cancel()
            timers[timer] = Task { [weak self] in
                do { try await Task.sleep(for: duration) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.timers[timer] = nil
                if timer == .watchdog { log.notice("watchdog: attempt timed out") }
                self.handle(.timerFired(timer))
            }
        case .cancelTimer(let timer):
            timers.removeValue(forKey: timer)?.cancel()
        case .giveUp:
            giveUpConnecting()
        }
    }

    /// Stops retrying and goes back to the device list with an error, so the app doesn't keep
    /// the radio busy forever when the headphones are off or out of range.
    func giveUpConnecting() {
        let name = selectedDevice?.name ?? String(localized: "the headphones")
        log.notice("giving up after \(self.machine.failedAttempts) failed attempts")
        deselect(forgetLastDevice: false)
        connectionError = LocalizedStringResource("Couldn't reach \(name). Make sure it's turned on and nearby, then try again.")
    }

    /// Drops the link and stops everything the state machine had running.
    func disconnect() {
        handle(.deselected)
        known.removeAll()
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
