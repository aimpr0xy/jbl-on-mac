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
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == JBLUUID.notify, let bytes = characteristic.value.map([UInt8].init) else { return }
        for reply in JBLReply.decode(bytes) {
            apply(reply)
        }
    }

    /// Copies a decoded reply into the observable state.
    func apply(_ reply: JBLReply) {
        switch reply {
        case .listeningMode(let mode): selectedMode = mode
        case .noiseCancelingLevel(let level): noiseCancelingLevel = level
        case .ambientAwareLevel(let level): ambientAwareLevel = level
        case .spatialAudio(let mode): selectedSpatialMode = mode
        case .smartAudio(let mode): selectedSmartMode = mode
        case .balance(let value): balance = value
        case .volumeLimiter(let enabled): volumeLimiterEnabled = enabled
        case .equalizer(let preset): selectedEqualizer = preset
        case .soundLevelOptimizer(let enabled): soundLevelOptimizerEnabled = enabled
        case .callSound(let setting): callSoundSetting = setting
        case .callVoice(let setting): callVoiceSetting = setting
        case .voiceAware(let enabled, let level):
            voiceAwareEnabled = enabled
            voiceAwareLevel = level
        case .battery(let part, let percent):
            switch part {
            case .left: leftBattery = percent
            case .right: rightBattery = percent
            case .chargingCase: caseBattery = percent
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
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
