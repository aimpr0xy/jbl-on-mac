import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

/// Only used through `HeadphoneController.log`, which adds the device info to every line.
let logger = Logger(subsystem: "JblOnMac", category: "BLE")

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

    /// The protocol dialect of the selected device.
    var model: JBLModel {
        selectedDevice.map { JBLModel(name: $0.name) } ?? .unknown
    }

    let writeUUID = JBLUUID.write
    let notifyUUID = JBLUUID.notify

    @ObservationIgnored var central: CBCentralManager!
    @ObservationIgnored var peripheral: CBPeripheral?
    @ObservationIgnored var writeCharacteristic: CBCharacteristic?
    /// Commands written but not yet acknowledged, oldest first; write-with-response results
    /// arrive in order, and the callback doesn't say which command it is for.
    @ObservationIgnored var pendingWrites: [JBLCommand] = []
    /// Tune 230NC: packets of the equalizer upload still to send, each after the previous one is
    /// acked. Nil while no upload is running.
    @ObservationIgnored var uploadRemaining: [JBLCommand]?
    /// Tune 230NC: a preset picked while an upload was running, sent once it finishes.
    @ObservationIgnored var queuedEqualizer: EqualizerPreset?
    /// Tune 230NC: bytes of the chunked reply being received. Nil while none is.
    @ObservationIgnored var downloadBuffer: [UInt8]?

    @ObservationIgnored var inquiry: IOBluetoothDeviceInquiry?
    @ObservationIgnored var isDiscovering = false
    /// The wait between one inquiry and the next; cancelled when discovery stops.
    /// Whether the device lookup was running when a connect started and should come back after it.
    @ObservationIgnored var resumeDiscoveryAfterConnect = false
    @ObservationIgnored var inquiryPause: Task<Void, Never>?
    @ObservationIgnored var nearby: [String: IOBluetoothDevice] = [:]
    @ObservationIgnored var nearbyTracker = NearbyTracker()
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

    // MARK: - Logging

    /// Logs a message prefixed with the selected device and what it reported about itself, so
    /// every line in a shared log shows which model and firmware it came from.
    func log(_ message: String, level: OSLogType = .default) {
        let device = selectedDevice.map { "device=\"\($0.name)\" model=\(String(describing: model)) \(state.info.logDescription ?? "info=unknown")" } ?? "device=none"
        logger.log(level: level, "[\(device, privacy: .public)] \(message, privacy: .public)")
    }

    /// Device info of the selected device, saved per device (by classic Bluetooth address) so log
    /// lines include it from the start of the next connection, before it is read again.
    var savedDeviceInfo: DeviceInfo? {
        get {
            guard let key = deviceInfoKey,
                  let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(DeviceInfo.self, from: data)
        }
        set {
            guard let key = deviceInfoKey else { return }
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
        }
    }

    private var deviceInfoKey: String? {
        selectedDevice.map { "deviceInfo.\($0.address)" }
    }

    // MARK: - Selecting a device and controlling it over BLE

    /// Picks a connected headphone and opens its BLE link so its controls can be shown.
    func select(_ device: JBLDevice) {
        disconnect()
        stopDiscovery()
        selectedDevice = device
        state = DeviceState()
        state.info = savedDeviceInfo ?? DeviceInfo()
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
        let bytes = command.bytes
        log("sent \(String(describing: command)): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))", level: .debug)
        peripheral.writeValue(Data(bytes), for: writeCharacteristic, type: .withResponse)
    }

    /// Called when the headphones confirm or reject the oldest outstanding write. The UI is
    /// updated optimistically, so a failed write must be undone: ask the headphones for the real
    /// state.
    func writeCompleted(error: Error?) {
        guard !pendingWrites.isEmpty else { return }
        let command = pendingWrites.removeFirst()
        guard let error else { return }
        log("write failed for \(String(describing: command)): \(error.localizedDescription)", level: .error)
        // The rest of an upload is useless once one of its packets is lost.
        if command.refreshQuery == .queryEqualizerCurve {
            uploadRemaining = nil
            queuedEqualizer = nil
        }
        if let query = command.refreshQuery {
            send(query)
        }
    }

    /// Whether the BLE link is ready for writes, and the model is one we know how to write to.
    private var canSend: Bool { peripheral != nil && writeCharacteristic != nil && model.allowsWrites }

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
        send(model == .tune230NC ? .setTune230NCSmartAudio(smart) : .setSmartAudio(smart))
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
        state.equalizer = preset
        if model == .tune230NC {
            upload(preset)
        } else {
            send(.setEqualizer(preset))
        }
    }

    /// Tune 230NC: starts the chunked write of a preset, or queues it behind the running one so
    /// two uploads don't interleave.
    private func upload(_ preset: EqualizerPreset) {
        guard uploadRemaining == nil else {
            queuedEqualizer = preset
            return
        }
        var packets = JBLCommand.equalizerUpload(preset)
        send(packets.removeFirst())
        uploadRemaining = packets
    }

    /// Tune 230NC: sends the next upload packet once the headphones acked the previous one.
    func uploadPacketAcknowledged() {
        guard var remaining = uploadRemaining else { return }
        guard !remaining.isEmpty else {
            uploadRemaining = nil
            if let next = queuedEqualizer {
                queuedEqualizer = nil
                upload(next)
            }
            return
        }
        send(remaining.removeFirst())
        uploadRemaining = remaining
    }

    /// Sets what the touch controls of one earbud do.
    func select(_ control: GestureControl, for side: EarbudSide) {
        guard canSend else { return }
        send(model.gestureCommand(side, control, other: state.gestureControl(for: side.opposite)))
        if side == .left { state.leftGestureControl = control } else { state.rightGestureControl = control }
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
        if model == .tune230NC {
            send(.setTune230NCVoiceAware(enabled ? level : nil))
        } else {
            send(.setVoiceAware(enabled: enabled, level: level))
        }
    }

    func startScanning() {
        log("authorization=\(CBCentralManager.authorization.rawValue) state=\(self.central.state.rawValue)")
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
        // The Tune 230NC's LE side changes its private address every few minutes and isn't bonded
        // with the Mac, so a remembered identifier soon points at an address nobody answers on.
        if model != .tune230NC, let id = rememberedIdentifier,
           let match = central.retrievePeripherals(withIdentifiers: [id]).first {
            log("connecting to remembered peripheral \(id.uuidString)")
            known[id] = match
            handle(.attempt(.remembered(id)))
            return
        }
        // The headphones may already hold a BLE link to the system (e.g. via the audio
        // connection), in which case they don't advertise and a scan would never find them.
        let alreadyConnected = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "1800")])
        log("already connected: \(alreadyConnected.map { $0.name ?? "nil" }), target=\(self.selectedDevice?.name ?? "nil"), state=\(self.central.state.rawValue)")
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
        log("\(String(describing: event)) -> \(String(describing: actions))", level: .debug)
        if machine.phase != phase { status = Status(machine.phase) }
        for action in actions { perform(action) }
        // The machine dropped the link (failure, disconnect, timeout or deselect).
        if machine.current == nil {
            peripheral = nil
            writeCharacteristic = nil
            pendingWrites.removeAll()
            uploadRemaining = nil
            queuedEqualizer = nil
            downloadBuffer = nil
        }
    }

    private func perform(_ action: ConnectionStateMachine.Action) {
        switch action {
        case .beginAttempt:
            startScanning()
        case .connect(let id):
            guard central.state == .poweredOn, let target = known[id] else { return }
            if peripheral?.identifier != id {
                writeCharacteristic = nil
                pendingWrites.removeAll()
            }
            peripheral = target
            target.delegate = self
            log("connecting state=\(target.state.rawValue) name=\(target.name ?? "nil")")
            if target.state == .connected {
                target.discoverServices(nil)
            } else {
                central.connect(target)
            }
        case .scan:
            guard central.state == .poweredOn else { return }
            central.scanForPeripherals(withServices: nil)
        case .stopScan:
            // CoreBluetooth rejects scan commands unless the radio is on. There's nothing
            // to stop otherwise, and the machine can ask for this while Bluetooth is off.
            guard central.state == .poweredOn else { return }
            central.stopScan()
        case .cancel(let id):
            // Likewise, the link is already gone if Bluetooth isn't powered on.
            guard central.state == .poweredOn, let target = known[id] else { return }
            cancelConnection(target)
        case .discoverServices(let id):
            known[id]?.discoverServices(nil)
        case .startTimer(let timer, let duration):
            timers[timer]?.cancel()
            timers[timer] = Task { [weak self] in
                do { try await Task.sleep(for: duration) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.timers[timer] = nil
                if timer == .watchdog { self.log("watchdog: attempt timed out") }
                self.handle(.timerFired(timer))
            }
        case .cancelTimer(let timer):
            timers.removeValue(forKey: timer)?.cancel()
        case .giveUp:
            giveUpConnecting()
        }
    }

    /// Stops retrying and goes back to the device list, so the app doesn't keep the radio busy
    /// forever when the headphones are off or out of range.
    func giveUpConnecting() {
        log("giving up after \(self.machine.failedAttempts) failed attempts")
        deselect(forgetLastDevice: false)
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
        if status != kIOReturnSuccess { log("couldn't connect through macOS", level: .error) }
        finishConnecting()
    }
}
