import CoreBluetooth
import Foundation

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
        log("discovered name=\(name ?? "nil") rssi=\(RSSI.intValue) adv=\(String(describing: advertisementData))")
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fastPair = serviceData?[JBLUUID.fastPairService].map { Array($0) }
        var match = nameMatch(for: name)
        if match != .exact, let fastPair, let advertised = model.advertisementMatch(serviceData: fastPair) {
            match = advertised
        }
        guard match != .none else { return }
        known[peripheral.identifier] = peripheral
        handle(.discovered(peripheral.identifier, match))
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
