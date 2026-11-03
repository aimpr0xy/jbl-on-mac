import SwiftUI

/// Styled after the Bluetooth and Sound menus in Control Center: a bold header, circular
/// icon badges that fill with the accent color when active.
struct ContentView: View {
    let headphones: HeadphoneController
    /// Which screen of a connected device is showing.
    @State private var screen: Screen = .controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The noise control options only open once the headphones are connected; until
            // then the picked device stays in the list and its row shows the progress.
            if let device = headphones.selectedDevice, headphones.status == .connected {
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
                case .level(let mode):
                    LevelScreen(headphones: headphones, mode: mode, screen: $screen)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .balance:
                    BalanceScreen(headphones: headphones, screen: $screen)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .equalizer:
                    EqualizerScreen(headphones: headphones, screen: $screen)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .gestures(let side):
                    GesturesScreen(headphones: headphones, side: side, screen: $screen)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .calls:
                    CallFeaturesScreen(headphones: headphones, screen: $screen)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
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
}

#Preview {
    ContentView(headphones: HeadphoneController())
}
