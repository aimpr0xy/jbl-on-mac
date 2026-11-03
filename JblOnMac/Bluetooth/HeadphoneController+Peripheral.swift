import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

extension HeadphoneController: CBPeripheralDelegate {
    /// Once notifications are on, ask the headphones for their current state.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard characteristic.uuid == JBLUUID.notify, characteristic.isNotifying else { return }
        for query in model.initialQueries {
            send(query)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard characteristic.uuid == writeUUID else { return }
        writeCompleted(error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
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
        // Chunks of a Tune 230NC download are raw `<index> <bytes…>`, not frames. Each is acked.
        if downloadBuffer != nil, let index = bytes.first, index != 0xAA {
            downloadBuffer?.append(contentsOf: bytes.dropFirst())
            send(.acknowledgeDownload)
            return
        }
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
        case .gestureControl(let side, let control):
            if side == .left { state.leftGestureControl = control } else { state.rightGestureControl = control }
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
        case .acknowledged(let group, let status):
            guard group == 0x41 else { break }
            if status == 0 {
                uploadPacketAcknowledged()
            } else {
                // Rejected: stop the upload and show what the headphones actually use.
                log("equalizer upload rejected with status \(status)", level: .error)
                uploadRemaining = nil
                queuedEqualizer = nil
                send(.queryEqualizerCurve)
            }
        case .firmware(let version):
            state.info.firmware = version
            savedDeviceInfo = state.info
        case .caseFirmware(let version):
            state.info.caseFirmware = version
            savedDeviceInfo = state.info
        case .downloadStarted:
            downloadBuffer = []
            send(.acknowledgeDownload)
        case .downloadFinished:
            // Nil for a curve that isn't one of the presets, such as a custom one.
            if let buffer = downloadBuffer, let gains = JBLReply.equalizerGains(fromDownload: buffer) {
                state.equalizer = model.equalizerPresets.first { $0.tune230NCGains == gains }
            }
            downloadBuffer = nil
            send(.acknowledgeDownload)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        log("didDiscoverServices \((peripheral.services ?? []).map { $0.uuid.uuidString }) error=\(error.map { String(describing: $0) } ?? "nil")")
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
        log("didDiscoverCharacteristics service=\(service.uuid.uuidString) \((service.characteristics ?? []).map { $0.uuid.uuidString }) error=\(error.map { String(describing: $0) } ?? "nil")")
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
