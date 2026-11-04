import SwiftUI

/// The popover: its screens, and Bluetooth discovery while it is open.
struct ContentView: View {
    let headphones: HeadphoneController

    var body: some View {
        PopoverScreens(headphones: headphones)
            .task {
                // Show the paired devices right away; after that the list only changes when an
                // inquiry for nearby JBL products completes.
                headphones.refreshDevices()
                headphones.startDiscovery()
            }
            .onDisappear { headphones.stopDiscovery() }
    }
}

/// Styled after the Bluetooth and Sound menus in Control Center: a bold header, circular
/// icon badges that fill with the accent color when active. Kept apart from the discovery in
/// `ContentView`, whose IOBluetooth calls block on a Mac without Bluetooth, so tests can lay it out.
struct PopoverScreens: View {
    let headphones: HeadphoneController
    /// Which screen of a connected device is showing.
    @State private var screen: Screen = .controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The noise control options only open once the headphones are connected; until
            // then the picked device stays in the list and its row shows the progress.
            if headphones.selectedDevice != nil, headphones.status == .connected {
                connectedScreen
            } else {
                DeviceListView(headphones: headphones)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: headphones.status == .connected)
        .animation(.snappy, value: screen)
        .clipped()
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 280)
    }

    /// The screen of the connected device that is currently showing. Controls slide in from the
    /// left and every other screen from the right.
    @ViewBuilder
    private var connectedScreen: some View {
        if let device = headphones.selectedDevice {
            switch screen {
            case .controls:
                DeviceControlsView(headphones: headphones, device: device, screen: $screen)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .ambientSound:
                AmbientSoundScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .smartAudio:
                SmartAudioScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .spatialAudio:
                SpatialAudioScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case let .level(mode):
                LevelScreen(headphones: headphones, mode: mode, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .balance:
                BalanceScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .equalizer:
                EqualizerScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case let .gestures(side):
                GesturesScreen(headphones: headphones, side: side, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .calls:
                CallFeaturesScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .callSound:
                CallSoundScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .callVoice:
                CallVoiceScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .voiceAware:
                VoiceAwareScreen(headphones: headphones, screen: $screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

#Preview {
    ContentView(headphones: HeadphoneController())
}
