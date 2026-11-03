import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

extension HeadphoneController {

    /// Starts looking for nearby Bluetooth devices. Runs until `stopDiscovery()`.
    func startDiscovery() {
        // A running classic-Bluetooth inquiry hogs the radio and starves the BLE scan,
        // so only look for devices while the list is showing.
        guard !isDiscovering, selectedDevice == nil else { return }
        isDiscovering = true
        runInquiry()
    }

    func stopDiscovery() {
        isDiscovering = false
        inquiry?.stop()
    }

    func runInquiry() {
        let inquiry = inquiry ?? IOBluetoothDeviceInquiry(delegate: self)
        self.inquiry = inquiry
        inquiry?.inquiryLength = 6
        inquiry?.updateNewDeviceNames = true
        inquiry?.start()
    }

    /// Rebuilds the list from paired devices plus anything the inquiry found nearby.
    func refreshDevices() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var byAddress: [String: IOBluetoothDevice] = nearby
        for device in paired {
            if let address = device.addressString { byAddress[address] = device }
        }
        devices = byAddress.values
            .compactMap { device -> JBLDevice? in
                guard let name = device.name, name.localizedCaseInsensitiveContains("JBL"),
                      let address = device.addressString else { return nil }
                return JBLDevice(name: name, address: address, isConnected: device.isConnected())
            }
            .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
    }

    /// Pairs (if needed) and connects a device through macOS, so the user doesn't have
    /// to go through System Settings.
    func connect(_ device: JBLDevice) {
        guard let target = IOBluetoothDevice(addressString: device.address) else { return }
        connectionError = nil
        connectingAddress = device.address
        if target.isPaired() {
            openConnection(to: target)
        } else {
            let pair = IOBluetoothDevicePair(device: target)
            pairing = pair
            pair?.delegate = self
            if pair?.start() != kIOReturnSuccess {
                finishConnecting(error: "Couldn't start pairing")
            }
        }
    }

    func openConnection(to target: IOBluetoothDevice) {
        if target.openConnection(self) != kIOReturnSuccess {
            finishConnecting(error: "Couldn't connect")
        }
    }

    func finishConnecting(error: LocalizedStringResource?) {
        connectingAddress = nil
        pairing = nil
        connectionError = error
        refreshDevices()
    }
}

extension HeadphoneController: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        if let address = device.addressString { nearby[address] = device }
        refreshDevices()
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!,
                                        device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        refreshDevices()
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        // Keep scanning while the popup is open.
        if isDiscovering { runInquiry() }
    }
}

extension HeadphoneController: IOBluetoothDevicePairDelegate {
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        guard error == kIOReturnSuccess, let pair = sender as? IOBluetoothDevicePair,
              let device = pair.device() else {
            finishConnecting(error: "Pairing failed. Put the headphones in pairing mode and try again.")
            return
        }
        openConnection(to: device)
    }
}
