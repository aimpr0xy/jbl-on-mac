import CoreBluetooth
import os

extension HeadphoneController: CBPeripheralDelegate {
    /// Once notifications are on, ask the headphones for their current state.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error _: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, characteristic.uuid == JBLUUID.notify,
              characteristic.isNotifying else { return }
        for query in model.initialQueries {
            send(query)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, characteristic.uuid == writeUUID else { return }
        run(.writeCompleted(error: error?.localizedDescription))
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error _: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if characteristic.service?.uuid == DeviceInfo.service {
            guard let data = characteristic.value else { return }
            if state.info.set(DeviceInfo.string(from: data), for: characteristic.uuid) {
                savedDeviceInfo = state.info
                log("device info \(characteristic.uuid.uuidString) updated")
            }
            return
        }
        guard characteristic.uuid == JBLUUID.notify, let bytes = characteristic.value.map([UInt8].init) else { return }
        run(.notified(bytes))
    }

    /// Copies a decoded reply into the observable state, or reacts to it.
    func apply(_ reply: JBLReply) {
        if state.apply(reply) {
            return
        }
        switch reply {
        case let .firmware(version):
            state.info.firmware = version
            savedDeviceInfo = state.info
        case let .caseFirmware(version):
            state.info.caseFirmware = version
            savedDeviceInfo = state.info
        default:
            break // Stored values were applied by `DeviceState.apply(_:)` above.
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        let services = (peripheral.services ?? []).map(\.uuid.uuidString)
        log("didDiscoverServices \(services) error=\(describe(error))")
        // A device can have several LE links (the Tune 230NC has one that only does pairing). Forget
        // one without the JBL service so the next attempt looks for the right one.
        if !(peripheral.services ?? []).contains(where: { $0.uuid == JBLUUID.service }) {
            log("no JBL service on this link, forgetting it", level: .error)
            rememberedIdentifier = nil
        }
        for service in peripheral.services ?? [] {
            if service.uuid == DeviceInfo.service {
                peripheral.discoverCharacteristics(DeviceInfo.characteristics, for: service)
            } else {
                peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        let characteristics = (service.characteristics ?? []).map(\.uuid.uuidString)
        log("didDiscoverCharacteristics service=\(service.uuid.uuidString) \(characteristics) error=\(describe(error))")
        // Read the model, firmware and so on, so they show up in every following log line.
        if service.uuid == DeviceInfo.service {
            for characteristic in service.characteristics ?? [] {
                peripheral.readValue(for: characteristic)
            }
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == notifyUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == writeUUID {
                writeCharacteristic = characteristic
                handle(.linkReady(peripheral.identifier))
                rememberSelectedDevice()
            }
        }
    }
}
