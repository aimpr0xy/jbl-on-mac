import Foundation

/// Everything remembered between launches, kept in `UserDefaults`: the last device, each
/// device's LE link and each device's info. Per-device values are keyed by classic Bluetooth address.
struct DeviceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let lastDeviceKey = "lastDevice"
    private static let legacyIdentifierKey = "lePeripheralIdentifier"

    private static func identifierKey(for address: String) -> String {
        "lePeripheralIdentifier.\(address)"
    }

    private static func infoKey(for address: String) -> String {
        "deviceInfo.\(address)"
    }

    /// Name and classic Bluetooth address of the last device that connected successfully.
    /// Setting nil forgets it.
    var lastDevice: (name: String, address: String)? {
        get {
            guard let stored = defaults.dictionary(forKey: Self.lastDeviceKey) as? [String: String],
                  let name = stored["name"], let address = stored["address"] else { return nil }
            return (name, address)
        }
        nonmutating set {
            if let newValue {
                defaults.set(["name": newValue.name, "address": newValue.address], forKey: Self.lastDeviceKey)
            } else {
                defaults.removeObject(forKey: Self.lastDeviceKey)
            }
        }
    }

    /// Core Bluetooth identifier of the device's LE link. Before identifiers were stored per
    /// device there was a single global one; it is used until a per-device one is saved.
    func leIdentifier(for address: String) -> UUID? {
        guard let stored = defaults.string(forKey: Self.identifierKey(for: address))
            ?? defaults.string(forKey: Self.legacyIdentifierKey) else { return nil }
        return UUID(uuidString: stored)
    }

    /// Saves the device's LE identifier and drops the legacy global one.
    func setLEIdentifier(_ identifier: UUID?, for address: String) {
        defaults.set(identifier?.uuidString, forKey: Self.identifierKey(for: address))
        defaults.removeObject(forKey: Self.legacyIdentifierKey)
    }

    func deviceInfo(for address: String) -> DeviceInfo? {
        guard let data = defaults.data(forKey: Self.infoKey(for: address)) else { return nil }
        return try? JSONDecoder().decode(DeviceInfo.self, from: data)
    }

    func setDeviceInfo(_ info: DeviceInfo?, for address: String) {
        defaults.set(info.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.infoKey(for: address))
    }
}
