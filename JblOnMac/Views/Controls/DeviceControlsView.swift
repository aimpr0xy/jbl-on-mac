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

            SectionTitle("Ambient Sound Control")
            ForEach(ListeningMode.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: headphones.state.mode == option
                ) {
                    if option.hasLevel {
                        levelChevron(for: option)
                    }
                } action: {
                    headphones.select(option)
                }
            }

            // Only shown once the headphones report a smart audio and video state.
            if headphones.state.smartMode != nil {
                SectionTitle("Smart Audio & Video")
                    .padding(.top, 8)
                ForEach(SmartAudioMode.allCases) { option in
                    SelectableRow(
                        systemImage: option.systemImage,
                        title: option.title,
                        isActive: headphones.state.smartMode == option
                    ) {
                        EmptyView()
                    } action: {
                        headphones.select(option)
                    }
                }
            }

            // Only shown once the headphones report a spatial audio state, so models
            // without the feature don't get a dead section.
            if headphones.state.spatialMode != nil {
                SectionTitle("Spatial Audio")
                    .padding(.top, 8)
                ForEach(SpatialAudioMode.allCases) { option in
                    SelectableRow(
                        systemImage: option.systemImage,
                        title: option.title,
                        isActive: headphones.state.spatialMode == option
                    ) {
                        EmptyView()
                    } action: {
                        headphones.select(option)
                    }
                }
            }

            SectionTitle("Sound")
                .padding(.top, 8)
            SelectableRow(
                systemImage: "arrow.left.and.right",
                title: "Balance",
                isActive: false
            ) {
                DisclosureChevron()
            } action: {
                screen = .balance
            }

            SelectableRow(
                systemImage: "slider.vertical.3",
                title: "Equalizer",
                isActive: false
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

    /// Opens the strength screen for a mode.
    private func levelChevron(for mode: ListeningMode) -> some View {
        Button {
            screen = .level(mode)
        } label: {
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(String(localized: mode.title)) level"))
    }

    /// Left, right and case charge, styled like the AirPods entry in the system Bluetooth menu.
    @ViewBuilder
    private var batteryRow: some View {
        let levels: [(label: String, symbol: String, percent: Int?)] = [
            ("Left", "l.circle", headphones.state.leftBattery),
            ("Right", "r.circle", headphones.state.rightBattery),
            ("Case", "earbuds.case", headphones.state.caseBattery),
        ]
        if levels.contains(where: { $0.percent != nil }) {
            HStack(spacing: 14) {
                ForEach(levels, id: \.label) { level in
                    if let percent = level.percent {
                        Label("\(percent)%", systemImage: level.symbol)
                            .accessibilityLabel("\(level.label) \(percent) percent")
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
