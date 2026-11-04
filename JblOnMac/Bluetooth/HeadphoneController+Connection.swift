import CoreBluetooth
import Foundation
import os

extension HeadphoneController {
    func startScanning() {
        log("authorization=\(CBCentralManager.authorization.rawValue) state=\(central.state.rawValue)")
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
        let alreadyConnectedNames = alreadyConnected.map { $0.name ?? "nil" }
        log(
            "already connected: \(alreadyConnectedNames), target=\(selectedDevice?.name ?? "nil"), "
                + "state=\(central.state.rawValue)"
        )
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
        if matchesSelectedDeviceExactly(name: name) {
            return .exact
        }
        return matchesSelectedDevice(name: name) ? .fallback : .none
    }

    // MARK: - Running the connection state machine

    /// Feeds an event to the state machine and carries out what it asks for.
    func handle(_ event: ConnectionStateMachine.Event) {
        let phase = machine.phase
        let actions = machine.handle(event)
        log("\(String(describing: event)) -> \(String(describing: actions))", level: .debug)
        if machine.phase != phase {
            status = Status(machine.phase)
        }
        for action in actions {
            perform(action)
        }
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
        case let .connect(id):
            connect(toKnown: id)
        case .scan, .stopScan:
            setScanning(action == .scan)
        case let .cancel(id):
            // The link is already gone if Bluetooth isn't powered on.
            guard central.state == .poweredOn, let target = known[id] else { return }
            cancelConnection(target)
        case let .discoverServices(id):
            known[id]?.discoverServices(nil)
        case .startTimer, .cancelTimer:
            updateTimer(action)
        case .giveUp:
            giveUpConnecting()
        }
    }

    private func connect(toKnown id: UUID) {
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
    }

    /// CoreBluetooth rejects scan commands unless the radio is on. There's nothing to start or
    /// stop otherwise, and the machine can ask for this while Bluetooth is off.
    private func setScanning(_ scanning: Bool) {
        guard central.state == .poweredOn else { return }
        if scanning {
            central.scanForPeripherals(withServices: nil)
        } else {
            central.stopScan()
        }
    }

    private func updateTimer(_ action: ConnectionStateMachine.Action) {
        switch action {
        case let .startTimer(timer, duration):
            startTimer(timer, duration)
        case let .cancelTimer(timer):
            timers.removeValue(forKey: timer)?.cancel()
        default:
            break // Only timer actions are passed in.
        }
    }

    private func startTimer(_ timer: ConnectionStateMachine.Timer, _ duration: Duration) {
        timers[timer]?.cancel()
        timers[timer] = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, !Task.isCancelled else { return }
            timers[timer] = nil
            if timer == .watchdog {
                log("watchdog: attempt timed out")
            }
            handle(.timerFired(timer))
        }
    }

    /// Stops retrying and goes back to the device list, so the app doesn't keep the radio busy
    /// forever when the headphones are off or out of range.
    func giveUpConnecting() {
        log("giving up after \(machine.failedAttempts) failed attempts")
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
}
