import CoreBluetooth
import Foundation
import os

extension HeadphoneController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("didUpdateState \(central.state.rawValue)")
        isBluetoothOff = central.state == .poweredOff
        if central.state == .poweredOn {
            if selectedDevice != nil {
                startScanning()
            }
        } else if selectedDevice != nil {
            status = central.state == .unauthorized ? .unauthorized : .bluetoothOff
        }
    }

    func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fastPair = serviceData?[JBLUUID.fastPairService].map { Array($0) }
        var match = nameMatch(for: name)
        if match != .exact, let fastPair, let advertised = model.advertisementMatch(serviceData: fastPair) {
            match = advertised
        }
        log(
            Self.discoveryLogLine(name: name, rssi: RSSI.intValue, fastPairData: fastPair),
            level: Self.discoveryLogLevel(for: match)
        )
        guard match != .none else { return }
        known[peripheral.identifier] = peripheral
        handle(.discovered(peripheral.identifier, match))
    }

    /// Advertisements from unrelated devices in range stay at `.debug`, which the system doesn't persist.
    static func discoveryLogLevel(for match: ConnectionStateMachine.NameMatch) -> OSLogType {
        match == .none ? .debug : .default
    }

    /// Only the fields used for matching (name, RSSI, Fast Pair service data), never the whole advertisement.
    static func discoveryLogLine(name: String?, rssi: Int, fastPairData: [UInt8]?) -> String {
        let fastPair = fastPairData.map { $0.map { String(format: "%02x", $0) }.joined() } ?? "nil"
        return "discovered name=\(name ?? "nil") rssi=\(rssi) fastPair=\(fastPair)"
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("didConnect \(peripheral.identifier.uuidString) name=\(peripheral.name ?? "nil")")
        // A link we already replaced or cancelled isn't the headphones' link to remember.
        if peripheral.identifier == self.peripheral?.identifier {
            rememberedIdentifier = peripheral.identifier
        }
        expectedDisconnects.remove(peripheral.identifier)
        handle(.didConnect(peripheral.identifier))
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log("didFailToConnect error=\(describe(error))")
        cancelling[peripheral.identifier] = nil
        if expectedDisconnects.remove(peripheral.identifier) != nil {
            return
        }
        handle(.didFailToConnect(peripheral.identifier))
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let expected = expectedDisconnects.contains(peripheral.identifier)
        log("didDisconnect error=\(describe(error)) expected=\(expected)")
        cancelling[peripheral.identifier] = nil
        if expectedDisconnects.remove(peripheral.identifier) != nil {
            return
        }
        handle(.didDisconnect(peripheral.identifier))
    }
}
