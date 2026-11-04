import AppKit
import CoreBluetooth
import Foundation
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

    /// Finds nearby JBL products and connects them through macOS; the list below comes from it.
    let discovery: DeviceDiscovery

    var devices: [JBLDevice] {
        get { discovery.devices }
        set { discovery.devices = newValue }
    }

    var selectedDevice: JBLDevice?
    var status: Status = .idle
    /// Whether the Mac's Bluetooth radio is switched off. Tracked separately from `status`,
    /// which only reflects Bluetooth while a device is selected.
    var isBluetoothOff = false
    /// Values reported by the selected headphones; reset as a whole when the selection changes.
    var state = DeviceState()
    /// Address of the device currently being paired / connected from the list.
    var connectingAddress: String? {
        get { discovery.connectingAddress }
        set { discovery.connectingAddress = newValue }
    }

    /// The protocol dialect of the selected device.
    var model: JBLModel {
        selectedDevice.map { JBLModel(name: $0.name) } ?? .unknown
    }

    /// What is remembered between launches.
    let deviceStore = DeviceStore()

    let writeUUID = JBLUUID.write
    let notifyUUID = JBLUUID.notify

    @ObservationIgnored let central = CBCentralManager(delegate: nil, queue: .main)
    @ObservationIgnored var peripheral: CBPeripheral?
    @ObservationIgnored var writeCharacteristic: CBCharacteristic?
    /// Decides what to write and how to react to replies; this class carries out its actions.
    @ObservationIgnored var pipeline = CommandPipeline()
    /// The timeout of an equalizer upload or download.
    @ObservationIgnored var transferTimer: Task<Void, Never>?

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

    init(classicBluetooth: (any ClassicBluetooth)? = nil) {
        discovery = DeviceDiscovery(bluetooth: classicBluetooth ?? IOBluetoothClassic())
        super.init()
        discovery.log = { [weak self] message, level in self?.log(message, level: level) }
        // Created without a delegate because `self` is unavailable before `super.init()`.
        central.delegate = self
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
        guard peripheral != nil, writeCharacteristic != nil else { return }
        run(.send(command))
    }
}
