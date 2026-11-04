import Foundation
import IOBluetooth

/// A classic Bluetooth device as discovery sees it.
protocol ClassicBluetoothDevice {
    var name: String? { get }
    var address: String? { get }
    var isConnected: Bool { get }
    var isPaired: Bool { get }
}

/// What the classic Bluetooth stack reports back, after a call that takes a while.
enum ClassicBluetoothEvent {
    case deviceFound(any ClassicBluetoothDevice)
    case inquiryCompleted(aborted: Bool)
    /// `address` is nil when pairing failed.
    case pairingFinished(address: String?)
    case connectionFinished(succeeded: Bool)
}

/// The IOBluetooth calls `DeviceDiscovery` needs, so tests can replace them.
protocol ClassicBluetooth: AnyObject {
    /// Receives the results of the calls below that finish later.
    var onEvent: ((ClassicBluetoothEvent) -> Void)? { get set }

    func pairedDevices() -> [any ClassicBluetoothDevice]
    func device(address: String) -> (any ClassicBluetoothDevice)?
    /// Runs one inquiry for nearby devices. Ends with `inquiryCompleted`.
    func startInquiry()
    func stopInquiry()
    /// Returns false if pairing couldn't start; otherwise ends with `pairingFinished`.
    func startPairing(address: String) -> Bool
    /// Returns false if the connection couldn't start; otherwise ends with `connectionFinished`.
    func openConnection(address: String) -> Bool
}

struct IOBluetoothClassicDevice: ClassicBluetoothDevice {
    let device: IOBluetoothDevice

    var name: String? {
        device.name
    }

    var address: String? {
        device.addressString
    }

    var isConnected: Bool {
        device.isConnected()
    }

    var isPaired: Bool {
        device.isPaired()
    }
}

/// `ClassicBluetooth` on top of IOBluetooth.
final class IOBluetoothClassic: NSObject, ClassicBluetooth {
    var onEvent: ((ClassicBluetoothEvent) -> Void)?
    private var inquiry: IOBluetoothDeviceInquiry?
    // periphery:ignore - only held so the pairing object stays alive until it calls back.
    private var pairing: IOBluetoothDevicePair?

    func pairedDevices() -> [any ClassicBluetoothDevice] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.map { IOBluetoothClassicDevice(device: $0) }
    }

    func device(address: String) -> (any ClassicBluetoothDevice)? {
        IOBluetoothDevice(addressString: address).map { IOBluetoothClassicDevice(device: $0) }
    }

    func startInquiry() {
        let inquiry = inquiry ?? IOBluetoothDeviceInquiry(delegate: self)
        self.inquiry = inquiry
        inquiry?.updateNewDeviceNames = true
        // Otherwise a device found before isn't reported again, and would look like it left.
        inquiry?.clearFoundDevices()
        inquiry?.start()
    }

    func stopInquiry() {
        inquiry?.stop()
    }

    func startPairing(address: String) -> Bool {
        guard let target = IOBluetoothDevice(addressString: address) else { return false }
        let pair = IOBluetoothDevicePair(device: target)
        pairing = pair
        pair?.delegate = self
        return pair?.start() == kIOReturnSuccess
    }

    func openConnection(address: String) -> Bool {
        IOBluetoothDevice(addressString: address)?.openConnection(self) == kIOReturnSuccess
    }

    /// Delegate callback for `IOBluetoothDevice.openConnection(_:)`.
    @objc func connectionComplete(_: IOBluetoothDevice!, status: IOReturn) {
        onEvent?(.connectionFinished(succeeded: status == kIOReturnSuccess))
    }
}

extension IOBluetoothClassic: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        onEvent?(.deviceFound(IOBluetoothClassicDevice(device: device)))
    }

    func deviceInquiryDeviceNameUpdated(_: IOBluetoothDeviceInquiry!,
                                        device _: IOBluetoothDevice!, devicesRemaining _: UInt32) {
        // The list is rebuilt once the inquiry completes, with the names it found.
    }

    func deviceInquiryComplete(_: IOBluetoothDeviceInquiry!, error _: IOReturn, aborted: Bool) {
        onEvent?(.inquiryCompleted(aborted: aborted))
    }
}

extension IOBluetoothClassic: IOBluetoothDevicePairDelegate {
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        let pair = sender as? IOBluetoothDevicePair
        let address = error == kIOReturnSuccess ? pair?.device()?.addressString : nil
        pairing = nil
        onEvent?(.pairingFinished(address: address))
    }
}
