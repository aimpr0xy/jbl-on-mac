import SwiftUI

struct DeviceListView: View {
    let headphones: HeadphoneController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "JBL on Mac") {
                EmptyView()
            }

            if headphones.isBluetoothOff {
                bluetoothOffState
            } else {
                if headphones.devices.isEmpty {
                    searchingState
                }

                ForEach(headphones.devices) { device in
                    DeviceRow(headphones: headphones, device: device)
                }
            }
        }
    }

    /// Shown instead of the device list while Bluetooth is turned off.
    private var bluetoothOffState: some View {
        VStack(spacing: 8) {
            Image(systemName: "slash.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Bluetooth is off")
                .font(.headline)
            Text("Turn on Bluetooth to find your JBL products.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Shown while Bluetooth is on but no JBL product has been found or remembered yet.
    private var searchingState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Discovering")
                .font(.headline)
            Text("Turn on your JBL headphones and keep them close to your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
}
