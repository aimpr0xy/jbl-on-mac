import SwiftUI

/// Clicking a device connects it (pairing first if needed) and, once connected, opens its
/// controls. Progress is shown in the row's description instead of a separate screen.
struct DeviceRow: View {
    let headphones: HeadphoneController
    let device: JBLDevice

    var body: some View {
        let isPairing = headphones.connectingAddress == device.address
        let isOpening = headphones.selectedDevice?.address == device.address
        let isBusy = isPairing || isOpening
        SelectableRow(
            systemImage: "headphones",
            title: device.name,
            subtitle: subtitle(isPairing: isPairing, isOpening: isOpening),
            isActive: device.isConnected
        ) {
            if isBusy, headphones.status != .bluetoothOff, headphones.status != .unauthorized {
                ProgressView().controlSize(.small)
            } else if device.isConnected {
                DisclosureChevron()
            }
        } action: {
            if isOpening {
                // Tapping a device that's still connecting cancels it.
                headphones.deselect()
            } else if device.isConnected {
                headphones.select(device)
            } else {
                headphones.connect(device)
            }
        }
        .disabled((headphones.connectingAddress != nil && !isPairing)
                  || (headphones.selectedDevice != nil && !isOpening))
    }

    private func subtitle(isPairing: Bool, isOpening: Bool) -> String? {
        if isPairing { return "Connecting…" }
        if isOpening {
            switch headphones.status {
            case .bluetoothOff: return "Bluetooth is off"
            case .unauthorized: return "Allow Bluetooth in System Settings"
            default: return "Connecting…"
            }
        }
        return device.isConnected ? nil : "Not Connected"
    }
}
