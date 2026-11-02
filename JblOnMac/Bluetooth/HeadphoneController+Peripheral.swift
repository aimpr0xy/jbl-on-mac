import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

extension HeadphoneController: CBPeripheralDelegate {
    /// Once notifications are on, ask the headphones for their current state.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == JBLUUID.notify, characteristic.isNotifying else { return }
        for query in JBLCommand.initialQueries {
            send(query)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == writeUUID else { return }
        writeCompleted(error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == JBLUUID.notify, let bytes = characteristic.value.map([UInt8].init) else { return }
        for reply in JBLReply.decode(bytes) {
            apply(reply)
        }
    }

    /// Copies a decoded reply into the observable state.
    func apply(_ reply: JBLReply) {
        switch reply {
        case .listeningMode(let mode): state.mode = mode
        case .noiseCancelingLevel(let level): state.noiseCancelingLevel = level
        case .ambientAwareLevel(let level): state.ambientAwareLevel = level
        case .spatialAudio(let mode): state.spatialMode = mode
        case .smartAudio(let mode): state.smartMode = mode
        case .balance(let value): state.balance = value
        case .volumeLimiter(let enabled): state.volumeLimiterEnabled = enabled
        case .equalizer(let preset): state.equalizer = preset
        case .soundLevelOptimizer(let enabled): state.soundLevelOptimizerEnabled = enabled
        case .callSound(let setting): state.callSoundSetting = setting
        case .callVoice(let setting): state.callVoiceSetting = setting
        case .voiceAware(let enabled, let level):
            state.voiceAwareEnabled = enabled
            state.voiceAwareLevel = level
        case .battery(let part, let percent):
            switch part {
            case .left: state.leftBattery = percent
            case .right: state.rightBattery = percent
            case .chargingCase: state.caseBattery = percent
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        log.notice("didDiscoverServices \((peripheral.services ?? []).map { $0.uuid.uuidString }, privacy: .public) error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public)")
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        log.notice("didDiscoverCharacteristics service=\(service.uuid.uuidString, privacy: .public) \((service.characteristics ?? []).map { $0.uuid.uuidString }, privacy: .public) error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public)")
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == notifyUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == writeUUID {
                writeCharacteristic = characteristic
                // Only count the attempt as a success once the link is usable; a link that
                // connects but never shows its services should still count toward giving up.
                failedAttempts = 0
                status = .connected
            }
        }
    }
}
