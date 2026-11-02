import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

extension HeadphoneController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.notice("didUpdateState \(central.state.rawValue)")
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
        log.notice("discovered name=\(name ?? "nil", privacy: .public) rssi=\(RSSI.intValue) adv=\(String(describing: advertisementData), privacy: .public)")
        guard matchesSelectedDevice(name: name) else { return }
        if matchesSelectedDeviceExactly(name: name) {
            fallbackPeripheral = nil
            central.stopScan()
            connectToHeadphones(peripheral)
        } else if fallbackPeripheral == nil {
            // Wait briefly for an exact match before settling for a differently named JBL.
            fallbackPeripheral = peripheral
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let fallback = self.fallbackPeripheral, fallback === peripheral,
                      self.peripheral == nil, self.selectedDevice != nil else { return }
                self.fallbackPeripheral = nil
                self.central.stopScan()
                self.connectToHeadphones(fallback)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.notice("didConnect \(peripheral.identifier.uuidString, privacy: .public) name=\(peripheral.name ?? "nil", privacy: .public)")
        rememberedIdentifier = peripheral.identifier
        expectedDisconnects.remove(peripheral.identifier)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log.notice("didFailToConnect error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public)")
        cancelling[peripheral.identifier] = nil
        failedAttempts += 1
        retryConnecting()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log.notice("didDisconnect error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public) expected=\(self.expectedDisconnects.contains(peripheral.identifier))")
        cancelling[peripheral.identifier] = nil
        if expectedDisconnects.remove(peripheral.identifier) != nil { return }
        // Ignore the late callback for a link we already replaced with a new attempt.
        if let current = self.peripheral, current !== peripheral { return }
        writeCharacteristic = nil
        self.peripheral = nil
        retryConnecting()
    }

    /// Tries again after a failure or a dropped link, as long as a device is selected. The delay
    /// doubles with each failed attempt (1, 2, 4, 8 s); after `maxFailedAttempts` it gives up.
    func retryConnecting() {
        guard selectedDevice != nil else { return }
        guard failedAttempts < maxFailedAttempts else {
            giveUpConnecting()
            return
        }
        status = .connecting
        connectAttempt += 1
        let attempt = connectAttempt
        let delay = 1 << max(failedAttempts - 1, 0)
        log.notice("retrying in \(delay)s (failed attempts: \(self.failedAttempts))")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.connectAttempt == attempt, self.selectedDevice != nil,
                  self.peripheral == nil else { return }
            self.startScanning()
        }
    }
}
