import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct PersistenceTests {
        @Test func rememberedIdentifierIsStoredPerDevice() {
            ControllerFixture.withController { controller in
                #expect(controller.rememberedIdentifier == nil)
                let id = UUID()
                controller.rememberedIdentifier = id
                #expect(controller.rememberedIdentifier == id)
                #expect(UserDefaults.standard.string(forKey: "lePeripheralIdentifier.AA-BB-CC-DD-EE-FF") == id
                    .uuidString)
            }
        }

        @Test func rememberedIdentifierFallsBackToTheLegacyGlobalOne() {
            ControllerFixture.withController { controller in
                let legacy = UUID()
                UserDefaults.standard.set(legacy.uuidString, forKey: "lePeripheralIdentifier")
                #expect(controller.rememberedIdentifier == legacy)

                let newer = UUID()
                controller.rememberedIdentifier = newer
                #expect(controller.rememberedIdentifier == newer)
                #expect(UserDefaults.standard.string(forKey: "lePeripheralIdentifier") == nil)
            }
        }

        @Test func rememberedIdentifierNeedsASelectedDevice() {
            ControllerFixture.withController(selecting: nil) { controller in
                controller.rememberedIdentifier = UUID()
                #expect(controller.rememberedIdentifier == nil)
                #expect(UserDefaults.standard.string(forKey: "lePeripheralIdentifier") == nil)
            }
        }

        @Test func rememberSelectedDeviceStoresNameAndAddress() {
            ControllerFixture.withController { controller in
                controller.rememberSelectedDevice()
                let stored = UserDefaults.standard.dictionary(forKey: "lastDevice") as? [String: String]
                #expect(stored == ["name": "JBL Tune 230NC TWS", "address": "AA-BB-CC-DD-EE-FF"])

                controller.clearLastDevice()
                #expect(UserDefaults.standard.dictionary(forKey: "lastDevice") == nil)
            }
        }

        @Test func rememberSelectedDeviceDoesNothingWithoutASelection() {
            ControllerFixture.withController(selecting: nil) { controller in
                controller.rememberSelectedDevice()
                #expect(UserDefaults.standard.dictionary(forKey: "lastDevice") == nil)
            }
        }

        @Test func deviceInfoIsSavedPerDeviceAndRoundTrips() {
            ControllerFixture.withController { controller in
                #expect(controller.savedDeviceInfo == nil)
                controller.savedDeviceInfo = DeviceInfo(firmware: "3.7.0", caseFirmware: "1.0.0")
                #expect(controller.savedDeviceInfo == DeviceInfo(firmware: "3.7.0", caseFirmware: "1.0.0"))
                controller.savedDeviceInfo = nil
                #expect(controller.savedDeviceInfo == nil)
            }
        }

        @Test func deviceInfoIsNotSavedWithoutASelection() {
            ControllerFixture.withController(selecting: nil) { controller in
                controller.savedDeviceInfo = DeviceInfo(firmware: "1.0")
                #expect(controller.savedDeviceInfo == nil)
            }
        }

        @Test func noLastDeviceMeansNothingIsSelectedOnLaunch() {
            ControllerFixture.withController(selecting: nil) { controller in
                controller.selectLastDeviceIfConnected()
                #expect(controller.selectedDevice == nil)
            }
        }
    }
}
