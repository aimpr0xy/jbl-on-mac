import SwiftUI

/// Main screen of a connected device: battery, ambient sound, smart audio, spatial audio, sound.
struct DeviceControlsView: View {
    let headphones: HeadphoneController
    let device: JBLDevice
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: LocalizedStringResource(stringLiteral: device.name), backLabel: "Back to devices") {
                headphones.deselect()
            } trailing: {
                EmptyView()
            }

            batteryRow

            // Each row is blue while something other than Off is selected, gray when off or
            // not yet reported.
            SelectableRow(
                systemImage: "ear.and.waveform",
                title: "Ambient Sound Control",
                subtitle: headphones.state.mode.map { String(localized: $0.title) },
                isActive: headphones.state.mode.map { $0 != .off } ?? false
            ) {
                DisclosureChevron()
            } action: {
                screen = .ambientSound
            }

            // Only shown once the headphones report a smart audio and video state.
            if let smart = headphones.state.smartMode {
                SelectableRow(
                    systemImage: "tv.and.mediabox",
                    title: "Smart Audio & Video",
                    subtitle: String(localized: smart.title),
                    isActive: smart != .off
                ) {
                    DisclosureChevron()
                } action: {
                    screen = .smartAudio
                }
            }

            // Only shown once the headphones report a spatial audio state, so models
            // without the feature don't get a dead row.
            if let spatial = headphones.state.spatialMode {
                SelectableRow(
                    systemImage: "person.spatialaudio.stereo.fill",
                    title: "Spatial Audio",
                    subtitle: String(localized: spatial.title),
                    isActive: spatial != .off
                ) {
                    DisclosureChevron()
                } action: {
                    screen = .spatialAudio
                }
            }

            SectionTitle("Sound")
                .padding(.top, 8)
            SelectableRow(
                systemImage: "arrow.left.and.right",
                title: "Balance",
                subtitle: headphones.state.balance.map(balanceDescription),
                // Blue while the balance is off centre.
                isActive: headphones.state.balance.map { $0 != 0 } ?? false
            ) {
                DisclosureChevron()
            } action: {
                screen = .balance
            }

            SelectableRow(
                systemImage: "slider.vertical.3",
                title: "Equalizer",
                subtitle: headphones.state.equalizer.map { String(localized: $0.title) },
                // Blue while a preset is applied; gray when off or not yet reported.
                isActive: headphones.state.equalizer.map { $0 != .off } ?? false
            ) {
                DisclosureChevron()
            } action: {
                screen = .equalizer
            }

            // Only shown once the headphones report a limiter state.
            if let limiter = headphones.state.volumeLimiterEnabled {
                SelectableRow(
                    systemImage: "ear.badge.checkmark",
                    title: "Safe Sound",
                    isActive: limiter
                ) {
                    EmptyView()
                } action: {
                    headphones.setVolumeLimiter(!limiter)
                }
            }

            SelectableRow(
                systemImage: "phone",
                title: "Calls",
                isActive: false
            ) {
                DisclosureChevron()
            } action: {
                screen = .calls
            }
        }
    }

    /// Describes a balance of -16 (left) ... 16 (right) in words.
    private func balanceDescription(_ value: Int) -> String {
        if value == 0 { return String(localized: "Centered") }
        return value < 0 ? String(localized: "Left \(-value)") : String(localized: "Right \(value)")
    }

    /// Left, right and case charge, styled like the AirPods entry in the system Bluetooth menu.
    @ViewBuilder
    private var batteryRow: some View {
        // Each part has its own spoken label, so translators can word and order it freely.
        let levels: [(symbol: String, percent: Int?, spoken: (Int) -> String)] = [
            ("l.circle", headphones.state.leftBattery, { String(localized: "Left \($0) percent") }),
            ("r.circle", headphones.state.rightBattery, { String(localized: "Right \($0) percent") }),
            ("earbuds.case", headphones.state.caseBattery, { String(localized: "Case \($0) percent") }),
        ]
        if levels.contains(where: { $0.percent != nil }) {
            HStack(spacing: 14) {
                ForEach(levels, id: \.symbol) { level in
                    if let percent = level.percent {
                        Label("\(percent)%", systemImage: level.symbol)
                            .accessibilityLabel(level.spoken(percent))
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}
