import SwiftUI

/// Call sound setting screen, reached from the Calls screen: one row per option.
struct CallSoundScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Sound Setting") {
                screen = .calls
            } trailing: {
                EmptyView()
            }

            ForEach(CallSoundSetting.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: headphones.state.callSoundSetting == option
                ) {
                    EmptyView()
                } action: {
                    headphones.select(option)
                }
            }
        }
    }
}

/// Call voice setting screen, reached from the Calls screen: one row per option.
struct CallVoiceScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Voice Setting") {
                screen = .calls
            } trailing: {
                EmptyView()
            }

            ForEach(CallVoiceSetting.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: headphones.state.callVoiceSetting == option
                ) {
                    EmptyView()
                } action: {
                    headphones.select(option)
                }
            }
        }
    }
}

/// Voice aware screen, reached from the Calls screen: Off, then one row per level.
struct VoiceAwareScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        let voiceAware = headphones.state.voiceAwareEnabled ?? false
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Voice Aware") {
                screen = .calls
            } trailing: {
                EmptyView()
            }

            SelectableRow(
                systemImage: "slash.circle",
                title: "Off",
                isActive: !voiceAware
            ) {
                EmptyView()
            } action: {
                headphones.setVoiceAware(enabled: false)
            }

            ForEach(VoiceAwareLevel.allCases) { option in
                SelectableRow(
                    systemImage: option.systemImage,
                    title: option.title,
                    isActive: voiceAware && headphones.state.voiceAwareLevel == option
                ) {
                    EmptyView()
                } action: {
                    headphones.select(option)
                }
            }
        }
    }
}
