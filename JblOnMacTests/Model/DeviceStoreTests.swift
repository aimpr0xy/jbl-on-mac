import Foundation
@testable import JblOnMac
import Testing

struct DeviceStoreTests {
    private let suiteName = "DeviceStoreTests.\(UUID().uuidString)"

    private func withStore(_ body: (DeviceStore, UserDefaults) -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(DeviceStore(defaults: defaults), defaults)
    }

    @Test func lastDeviceRoundTripsAndUsesTheExistingKey() throws {
        try withStore { store, defaults in
            #expect(store.lastDevice == nil)
            store.lastDevice = ("Tune", "AA-BB")
            #expect(store.lastDevice?.name == "Tune")
            #expect(store.lastDevice?.address == "AA-BB")
            #expect(defaults.dictionary(forKey: "lastDevice") as? [String: String]
                == ["name": "Tune", "address": "AA-BB"])
            store.lastDevice = nil
            #expect(store.lastDevice == nil)
            #expect(defaults.dictionary(forKey: "lastDevice") == nil)
        }
    }

    @Test func leIdentifierRoundTripsUnderThePerDeviceKey() throws {
        try withStore { store, defaults in
            let id = UUID()
            #expect(store.leIdentifier(for: "AA") == nil)
            store.setLEIdentifier(id, for: "AA")
            #expect(store.leIdentifier(for: "AA") == id)
            #expect(defaults.string(forKey: "lePeripheralIdentifier.AA") == id.uuidString)
            store.setLEIdentifier(nil, for: "AA")
            #expect(store.leIdentifier(for: "AA") == nil)
        }
    }

    @Test func legacyIdentifierIsUsedUntilAPerDeviceOneIsSavedThenRemoved() throws {
        try withStore { store, defaults in
            let legacy = UUID()
            defaults.set(legacy.uuidString, forKey: "lePeripheralIdentifier")
            #expect(store.leIdentifier(for: "AA") == legacy)
            #expect(store.leIdentifier(for: "BB") == legacy)

            let newer = UUID()
            store.setLEIdentifier(newer, for: "AA")
            #expect(store.leIdentifier(for: "AA") == newer)
            #expect(defaults.string(forKey: "lePeripheralIdentifier") == nil)
            #expect(store.leIdentifier(for: "BB") == nil)
        }
    }

    @Test func deviceInfoRoundTripsUnderThePerDeviceKey() throws {
        try withStore { store, defaults in
            let info = DeviceInfo(firmware: "3.7.0", caseFirmware: "1.0.0")
            #expect(store.deviceInfo(for: "AA") == nil)
            store.setDeviceInfo(info, for: "AA")
            #expect(store.deviceInfo(for: "AA") == info)
            #expect(defaults.data(forKey: "deviceInfo.AA") != nil)
            store.setDeviceInfo(nil, for: "AA")
            #expect(store.deviceInfo(for: "AA") == nil)
        }
    }

    @Test func valuesForDifferentAddressesDoNotOverwriteEachOther() throws {
        try withStore { store, _ in
            let first = UUID()
            let second = UUID()
            store.setLEIdentifier(first, for: "AA")
            store.setLEIdentifier(second, for: "BB")
            store.setDeviceInfo(DeviceInfo(firmware: "1"), for: "AA")
            store.setDeviceInfo(DeviceInfo(firmware: "2"), for: "BB")
            #expect(store.leIdentifier(for: "AA") == first)
            #expect(store.leIdentifier(for: "BB") == second)
            #expect(store.deviceInfo(for: "AA") == DeviceInfo(firmware: "1"))
            #expect(store.deviceInfo(for: "BB") == DeviceInfo(firmware: "2"))
        }
    }

    @Test func corruptDeviceInfoReadsAsNil() throws {
        try withStore { store, defaults in
            defaults.set(Data("nope".utf8), forKey: "deviceInfo.AA")
            #expect(store.deviceInfo(for: "AA") == nil)
        }
    }
}
