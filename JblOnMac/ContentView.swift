import SwiftUI

enum ListeningMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case noiseCanceling = "Noise Canceling"
    case ambientAware = "Ambient Aware"
    case talkThru = "Talk Thru"

    var id: String { rawValue }

    /// The modes the headphones report with one flag each (in flag order); `off` is all flags cleared.
    static let flagged: [ListeningMode] = [.noiseCanceling, .ambientAware, .talkThru]

    /// Whether the headphones have an adjustable strength for this mode.
    var hasLevel: Bool { self == .noiseCanceling || self == .ambientAware }

    var systemImage: String {
        switch self {
        case .noiseCanceling: "waveform.slash"
        case .ambientAware: "ear"
        case .talkThru: "person.wave.2"
        case .off: "slash.circle"
        }
    }
}

/// Raw values are the mode bytes seen in the JBL app's capture (1, 2, 3 while cycling through
/// the options; 1 was the initial state).
enum SpatialAudioMode: UInt8, CaseIterable, Identifiable {
    case off = 1
    case fixed = 2
    case headTracking = 3

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .fixed: "Fixed"
        case .headTracking: "Head Tracking"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "slash.circle"
        case .fixed: "person.spatialaudio.stereo.fill"
        case .headTracking: "person.spatialaudio.3d.fill"
        }
    }
}

/// The JBL app sends one 8-byte payload per mode. Which payload belongs to which mode was inferred
/// from the order the options were tapped in the capture (the app lists Off, Audio Mode, Video Mode);
/// the payloads are the only thing to change if a mode turns out to be mislabeled.
enum SmartAudioMode: CaseIterable, Identifiable {
    case off
    case audio
    case video

    var id: Self { self }

    var payload: [UInt8] {
        switch self {
        case .off: [0xC5, 0x00, 0x2E, 0x00, 0x18, 0x01, 0xFF, 0xFF]
        case .audio: [0x00, 0x01, 0x2E, 0x00, 0x18, 0x01, 0xFF, 0xFF]
        case .video: [0xC5, 0x00, 0x2E, 0x00, 0x78, 0x00, 0xFF, 0xFF]
        }
    }

    init?(payload: [UInt8]) {
        guard let match = Self.allCases.first(where: { $0.payload == payload }) else { return nil }
        self = match
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .audio: "Audio Mode"
        case .video: "Video Mode"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "slash.circle"
        case .audio: "music.note"
        case .video: "play.rectangle"
        }
    }
}

/// Styled after the Bluetooth and Sound menus in Control Center: a bold header, circular
/// icon badges that fill with the accent color when active.
struct ContentView: View {
    let headphones: HeadphoneController
    /// Mode whose strength screen is showing, if any.
    @State private var detailMode: ListeningMode?
    /// Whether the left / right balance screen is showing.
    @State private var showsBalance = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The noise control options only open once the headphones are connected; until
            // then the picked device stays in the list and its row shows the progress.
            if let device = headphones.selectedDevice, headphones.status == .connected {
                if let mode = detailMode {
                    levelScreen(for: mode)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if showsBalance {
                    balanceScreen
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    modeControls(for: device)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            } else {
                deviceList
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: headphones.status == .connected)
        .animation(.snappy, value: detailMode)
        .animation(.snappy, value: showsBalance)
        .clipped()
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 280)
        .task {
            // Look for nearby JBL products and keep the list fresh while the popup is open.
            headphones.startDiscovery()
            while !Task.isCancelled {
                headphones.refreshDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onDisappear { headphones.stopDiscovery() }
    }

    // MARK: - Device list

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("JBL on Mac") {
                EmptyView()
            }

            if headphones.devices.isEmpty {
                Text("Searching for nearby JBL products…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }

            ForEach(headphones.devices) { device in
                deviceRow(device)
            }

            if let error = headphones.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }

        }
    }

    /// Clicking a device connects it (pairing first if needed) and, once connected, opens its
    /// controls. Progress is shown in the row's description instead of a separate screen.
    private func deviceRow(_ device: JBLDevice) -> some View {
        let isPairing = headphones.connectingAddress == device.address
        let isOpening = headphones.selectedDevice?.address == device.address
        let isBusy = isPairing || isOpening
        return SelectableRow(
            systemImage: "headphones",
            title: device.name,
            subtitle: subtitle(for: device, isPairing: isPairing, isOpening: isOpening),
            isActive: device.isConnected
        ) {
            if isBusy, headphones.status != .bluetoothOff, headphones.status != .unauthorized {
                ProgressView().controlSize(.small)
            } else if device.isConnected {
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
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

    private func subtitle(for device: JBLDevice, isPairing: Bool, isOpening: Bool) -> String? {
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

    // MARK: - Device screen

    private func modeControls(for device: JBLDevice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            backHeader(for: device) { EmptyView() }

            batteryRow

            sectionTitle("Ambient Sound Control")
            ForEach(ListeningMode.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.rawValue,
                    isActive: headphones.selectedMode == option
                ) {
                    if option.hasLevel {
                        chevron(for: option)
                    }
                } action: {
                    headphones.select(option)
                }
            }

            // Only shown once the headphones report a smart audio and video state.
            if headphones.selectedSmartMode != nil {
                sectionTitle("Smart Audio & Video")
                    .padding(.top, 8)
                ForEach(SmartAudioMode.allCases) { option in
                    SelectableRow(
                        systemImage: option.systemImage,
                        title: option.title,
                        isActive: headphones.selectedSmartMode == option
                    ) {
                        EmptyView()
                    } action: {
                        headphones.select(option)
                    }
                }
            }

            // Only shown once the headphones report a spatial audio state, so models
            // without the feature don't get a dead section.
            if headphones.selectedSpatialMode != nil {
                sectionTitle("Spatial Audio")
                    .padding(.top, 8)
                ForEach(SpatialAudioMode.allCases) { option in
                    SelectableRow(
                        systemImage: option.systemImage,
                        title: option.title,
                        isActive: headphones.selectedSpatialMode == option
                    ) {
                        EmptyView()
                    } action: {
                        headphones.select(option)
                    }
                }
            }

            sectionTitle("Sound")
                .padding(.top, 8)
            SelectableRow(
                systemImage: "arrow.left.and.right",
                title: "Balance",
                isActive: false
            ) {
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } action: {
                showsBalance = true
            }
        }
    }

    /// Opens the strength screen for a mode.
    private func chevron(for mode: ListeningMode) -> some View {
        Button {
            detailMode = mode
        } label: {
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.rawValue) level")
    }

    /// Second screen with the strength slider for one mode, reached from the row's chevron.
    private func levelScreen(for mode: ListeningMode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    detailMode = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text(mode.rawValue)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            levelSlider(for: mode)
        }
    }

    /// Strength slider (1...7) for noise canceling or ambient aware.
    private func levelSlider(for mode: ListeningMode) -> some View {
        let binding = Binding<Double>(
            get: {
                Double((mode == .noiseCanceling ? headphones.noiseCancelingLevel
                                                : headphones.ambientAwareLevel) ?? 4)
            },
            set: { headphones.setLevel(Int($0), for: mode) }
        )
        return HStack(spacing: 8) {
            Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
            Slider(value: binding, in: 1...7, step: 1)
            Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityLabel("\(mode.rawValue) level")
    }

    /// Third-level screen with the left / right balance slider (-16 ... 16), reached from the Balance row.
    private var balanceScreen: some View {
        let binding = Binding<Double>(
            get: { Double(headphones.balance ?? 0) },
            set: { headphones.setBalance(Int($0)) }
        )
        let value = headphones.balance ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    showsBalance = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Balance")
                    .font(.headline)
                Spacer()
                Text(value == 0 ? "Center" : "\(value < 0 ? "L" : "R") \(abs(value))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                Text("L").foregroundStyle(.secondary)
                Slider(value: binding, in: -16...16, step: 1)
                Text("R").foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityLabel("Left right balance")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }

    /// Left, right and case charge, styled like the AirPods entry in the system Bluetooth menu.
    @ViewBuilder
    private var batteryRow: some View {
        let levels: [(label: String, symbol: String, percent: Int?)] = [
            ("Left", "l.circle", headphones.leftBattery),
            ("Right", "r.circle", headphones.rightBattery),
            ("Case", "earbuds.case", headphones.caseBattery),
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

    // MARK: - Pieces

    private func header<Trailing: View>(_ title: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func backHeader<Trailing: View>(for device: JBLDevice,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Button {
                headphones.deselect()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.callout.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to devices")

            Text(device.name)
                .font(.headline)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

}

/// A Control Center–style row: a circular icon badge (accent-filled when active), a title,
/// and an optional trailing view. The whole row is the click target and highlights on hover.
private struct SelectableRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    let isActive: Bool
    @ViewBuilder let trailing: Trailing
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering && isEnabled ? Color.primary.opacity(0.08) : .clear)
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    ContentView(headphones: HeadphoneController())
}
