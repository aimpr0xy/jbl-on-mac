import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

extension HeadphoneController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("didUpdateState \(central.state.rawValue)")
        isBluetoothOff = central.state == .poweredOff
        if central.state == .poweredOn {
            if selectedDevice != nil { startScanning() }
        } else if selectedDevice != nil {
            status = central.state == .unauthorized ? .unauthorized : .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        log("discovered name=\(name ?? "nil") rssi=\(RSSI.intValue) adv=\(String(describing: advertisementData))")
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fastPair = serviceData?[JBLUUID.fastPairService].map { Array($0) }
        var match = nameMatch(for: name)
        if model == .tune230NC, match != .exact, let fastPair {
            // Any other Fast Pair device sends `00 00` too, so that only counts as a fallback; a
            // link without the JBL service is dropped and forgotten when its services are listed.
            if fastPair.prefix(3).elementsEqual(JBLUUID.tune230NCFastPairModel) {
                match = .exact
            } else if fastPair == JBLUUID.tune230NCIdleFastPairData {
                match = .fallback
            }
        }
        guard match != .none else { return }
        known[peripheral.identifier] = peripheral
        handle(.discovered(peripheral.identifier, match))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("didConnect \(peripheral.identifier.uuidString) name=\(peripheral.name ?? "nil")")
        // A link we already replaced or cancelled isn't the headphones' link to remember.
        if peripheral.identifier == self.peripheral?.identifier {
            rememberedIdentifier = peripheral.identifier
        }
        expectedDisconnects.remove(peripheral.identifier)
        handle(.didConnect(peripheral.identifier))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log("didFailToConnect error=\(error.map { String(describing: $0) } ?? "nil")")
        cancelling[peripheral.identifier] = nil
        if expectedDisconnects.remove(peripheral.identifier) != nil { return }
        handle(.didFailToConnect(peripheral.identifier))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log("didDisconnect error=\(error.map { String(describing: $0) } ?? "nil") expected=\(self.expectedDisconnects.contains(peripheral.identifier))")
        cancelling[peripheral.identifier] = nil
        if expectedDisconnects.remove(peripheral.identifier) != nil { return }
        handle(.didDisconnect(peripheral.identifier))
    }
}
