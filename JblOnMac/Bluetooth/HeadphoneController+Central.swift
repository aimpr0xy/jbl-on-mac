import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

extension HeadphoneController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.notice("didUpdateState \(central.state.rawValue)")
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
        log.notice("discovered name=\(name ?? "nil", privacy: .public) rssi=\(RSSI.intValue) adv=\(String(describing: advertisementData), privacy: .public)")
        guard matchesSelectedDevice(name: name) else { return }
        central.stopScan()
        connectToHeadphones(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        rememberedIdentifier = peripheral.identifier
        expectedDisconnects.remove(peripheral.identifier)
        failedAttempts = 0
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log.notice("didFailToConnect error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public)")
        failedAttempts += 1
        retryConnecting()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log.notice("didDisconnect error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public) expected=\(self.expectedDisconnects.contains(peripheral.identifier))")
        if expectedDisconnects.remove(peripheral.identifier) != nil { return }
        // Ignore the late callback for a link we already replaced with a new attempt.
        if let current = self.peripheral, current !== peripheral { return }
        writeCharacteristic = nil
        self.peripheral = nil
        retryConnecting()
    }

    /// Tries again shortly after a failure or a dropped link, as long as a device is selected.
    func retryConnecting() {
        guard selectedDevice != nil else { return }
        status = .connecting
        connectAttempt += 1
        let attempt = connectAttempt
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.connectAttempt == attempt, self.selectedDevice != nil,
                  self.peripheral == nil else { return }
            self.startScanning()
        }
    }
}
