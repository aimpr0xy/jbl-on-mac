import Foundation
@testable import JblOnMac

/// Builds a `HeadphoneController` for tests without touching what the real app remembers.
/// The test host is the app itself, so `UserDefaults.standard` is the app's real defaults.
@MainActor
enum ControllerFixture {
    static let device = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA-BB-CC-DD-EE-FF", isConnected: true)

    static let keys = [
        "lastDevice",
        "lePeripheralIdentifier",
        "lePeripheralIdentifier.\(device.address)",
        "deviceInfo.\(device.address)"
    ]

    /// Controllers are kept alive for the whole run: a freed one can still receive Bluetooth
    /// callbacks, which crashes the test process.
    private static var controllers: [HeadphoneController] = []

    /// Runs `body` with a new controller and none of the remembered values, then puts back
    /// whatever was stored before.
    static func withController(
        selecting selected: JBLDevice? = ControllerFixture.device,
        _ body: (HeadphoneController) -> Void
    ) {
        let defaults = UserDefaults.standard
        let saved = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        let controller = HeadphoneController()
        controllers.append(controller)
        controller.selectedDevice = selected
        body(controller)
    }
}
