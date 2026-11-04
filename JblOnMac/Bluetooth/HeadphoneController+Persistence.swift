import Foundation
import IOBluetooth

/// What the controller remembers between launches: the last device, its LE link and its info.
/// Storage lives in `DeviceStore`; this passes the selected device's address to it.
extension HeadphoneController {
    /// Core Bluetooth identifier of the selected device's LE link, remembered after a successful
    /// connection. Nil until a connection succeeds, or when no device is selected.
    var rememberedIdentifier: UUID? {
        get { selectedDevice.flatMap { deviceStore.leIdentifier(for: $0.address) } }
        set {
            guard let address = selectedDevice?.address else { return }
            deviceStore.setLEIdentifier(newValue, for: address)
        }
    }

    /// Stops reopening the last device on the next launch.
    func clearLastDevice() {
        deviceStore.lastDevice = nil
    }

    /// Records the selected device as the one to reopen on the next launch.
    func rememberSelectedDevice() {
        guard let device = selectedDevice else { return }
        deviceStore.lastDevice = (device.name, device.address)
    }

    /// On launch, reopens the last used headphones if macOS still has them connected. Headphones
    /// that are off or away are left alone, so the app doesn't retry a link that can't succeed.
    func selectLastDeviceIfConnected() {
        guard let last = deviceStore.lastDevice,
              let target = IOBluetoothDevice(addressString: last.address),
              target.isPaired(), target.isConnected() else { return }
        select(JBLDevice(name: last.name, address: last.address, isConnected: true))
    }

    /// Device info of the selected device, so log lines include it from the start of the next
    /// connection, before it is read again. Nil when no device is selected.
    var savedDeviceInfo: DeviceInfo? {
        get { selectedDevice.flatMap { deviceStore.deviceInfo(for: $0.address) } }
        set {
            guard let address = selectedDevice?.address else { return }
            deviceStore.setDeviceInfo(newValue, for: address)
        }
    }
}
