import Foundation
import IOBluetooth

/// What the controller remembers between launches: the last device, its LE link and its info.
extension HeadphoneController {
    /// Core Bluetooth identifier of the headphones' LE link, remembered after a successful
    /// connection. Stored per device (by classic Bluetooth address), so each pair of headphones
    /// remembers its own LE link. Nil until a connection succeeds, or when no device is selected.
    var rememberedIdentifier: UUID? {
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

    /// Stops reopening the last device on the next launch.
    func clearLastDevice() {
        lastDevice = nil
    }

    /// Records the selected device as the one to reopen on the next launch.
    func rememberSelectedDevice() {
        guard let device = selectedDevice else { return }
        lastDevice = (device.name, device.address)
    }

    /// On launch, reopens the last used headphones if macOS still has them connected. Headphones
    /// that are off or away are left alone, so the app doesn't retry a link that can't succeed.
    func selectLastDeviceIfConnected() {
        guard let last = lastDevice,
              let target = IOBluetoothDevice(addressString: last.address),
              target.isPaired(), target.isConnected() else { return }
        select(JBLDevice(name: last.name, address: last.address, isConnected: true))
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
}
