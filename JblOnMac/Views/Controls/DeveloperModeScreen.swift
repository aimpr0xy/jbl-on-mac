import SwiftUI

/// Reached from the device's controls: what Bluetooth reports about it, for debugging.
struct DeveloperModeScreen: View {
    static let refreshInterval = Duration.seconds(1)

    let headphones: HeadphoneController
    let device: JBLDevice
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Developer Mode") {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 0) {
                detail("Name", device.name, systemImage: "headphones")
                detail("Signal Strength", rssiDescription, systemImage: "cellularbars")
                detail("Address", device.address, systemImage: "number")
                // Core Bluetooth hides the LE address behind an identifier that is private to this Mac.
                detail("LE Identifier", headphones.linkIdentifier?.uuidString ?? String(localized: "n/a"),
                       systemImage: "personalhotspot")
                // Only once the headphones have reported them.
                if let firmware = headphones.state.info.firmware {
                    detail("Firmware", firmware, systemImage: "cpu")
                }
                if let caseFirmware = headphones.state.info.caseFirmware {
                    detail("Case Firmware", caseFirmware, systemImage: "earbuds.case")
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            // The signal changes as the headphones move, so keep asking while the screen shows.
            while !Task.isCancelled {
                headphones.readLinkRSSI()
                do { try await Task.sleep(for: Self.refreshInterval) } catch { return }
            }
        }
    }

    /// A value under its label, with a badge like the one on the control rows.
    private func detail(_ label: LocalizedStringResource, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.quaternary))
                .accessibilityHidden(true)

            // Like the other menus: the name on top, its value below in the secondary caption.
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private var rssiDescription: String {
        Self.describe(rssi: headphones.linkRSSI)
    }

    /// "n/a" until the link has reported a signal.
    static func describe(rssi: Int?) -> String {
        rssi.map { String(localized: "\($0) dBm") } ?? String(localized: "n/a")
    }
}
