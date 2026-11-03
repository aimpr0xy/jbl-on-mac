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
        let match = nameMatch(for: name)
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
