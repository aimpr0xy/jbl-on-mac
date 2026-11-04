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

    // MARK: - Logging

    /// Logs a message prefixed with the selected device and what it reported about itself, so
    /// every line in a shared log shows which model and firmware it came from.
    func log(_ message: String, level: OSLogType = .default) {
        let device = selectedDevice
            .map {
                let info = state.info.logDescription ?? "info=unknown"
                return "device=\"\($0.name)\" model=\(String(describing: model)) \(info)"
            } ??
            "device=none"
        logger.log(level: level, "[\(device, privacy: .public)] \(message, privacy: .public)")
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
        if forgetLastDevice {
            clearLastDevice()
        }
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
        log(
            "sent \(String(describing: command)): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))",
            level: .debug
        )
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

    // periphery:ignore - IOBluetooth calls this by selector, so there is no Swift reference to it.
    /// Delegate callback for `IOBluetoothDevice.openConnection(_:)`.
    @objc func connectionComplete(_: IOBluetoothDevice!, status: IOReturn) {
        if status != kIOReturnSuccess {
            log("couldn't connect through macOS", level: .error)
        }
        finishConnecting()
    }
}
