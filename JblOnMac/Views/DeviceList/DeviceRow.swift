import SwiftUI

/// Clicking a device connects it (pairing first if needed) and, once connected, opens its
/// controls. Progress is shown as a spinner in the icon instead of a separate screen: gray while
/// macOS connects the device, blue while its settings connect.
struct DeviceRow: View {
    let headphones: HeadphoneController
    let device: JBLDevice

    var body: some View {
        let isPairing = headphones.connectingAddress == device.address
        let isOpening = headphones.selectedDevice?.address == device.address
        // Products we have no protocol for can't be controlled, so they can't be opened.
        let isSupported = JBLModel(name: device.name) != .unknown
        // Not while the settings link can't be made at all; the subtitle explains that.
        let isBusy = (isPairing || isOpening)
            && headphones.status != .bluetoothOff && headphones.status != .unauthorized
        SelectableRow(
            systemImage: isSupported ? "headphones" : "slash.circle",
            title: LocalizedStringResource(stringLiteral: device.name),
            subtitle: subtitle(isOpening: isOpening),
            isActive: device.isConnected && isSupported,
            isBusy: isBusy
        ) {
            if device.isConnected, isSupported, !isBusy {
                DisclosureChevron()
            }
        } action: {
            guard isSupported else { return }
            if isOpening {
                // Tapping a device that's still connecting cancels it.
                headphones.deselect()
            } else if device.isConnected {
                headphones.select(device)
            } else {
                headphones.connect(device)
            }
        }
        .disabled(!isSupported
                  || (headphones.connectingAddress != nil && !isPairing)
                  || (headphones.selectedDevice != nil && !isOpening))
        .help(isSupported ? "" : String(localized: "This product isn't supported yet"))
    }

    /// Only problems are spelled out; connection state is shown by the icon.
    private func subtitle(isOpening: Bool) -> String? {
        guard isOpening else { return nil }
        switch headphones.status {
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Allow Bluetooth in System Settings"
        default: return nil
        }
    }
}
