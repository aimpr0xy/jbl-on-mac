import SwiftUI

/// Call features screen, reached from the Calls row. Each section only shows once the
/// headphones report its state.
struct CallFeaturesScreen: View {
    let headphones: HeadphoneController
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Calls") {
                screen = .controls
            } trailing: {
                EmptyView()
            }

            if let optimizer = headphones.soundLevelOptimizerEnabled {
                SelectableRow(
                    systemImage: "ear.badge.waveform",
                    title: "Sound Level Optimizer",
                    isActive: optimizer
                ) {
                    EmptyView()
                } action: {
                    headphones.setSoundLevelOptimizer(!optimizer)
                }
            }

            if headphones.callSoundSetting != nil {
                SectionTitle("Sound Setting")
                    .padding(.top, 8)
                ForEach(CallSoundSetting.allCases) { option in
                    SelectableRow(
                        systemImage: option.systemImage,
                        title: option.title,
                        isActive: headphones.callSoundSetting == option
                    ) {
                        EmptyView()
                    } action: {
                        headphones.select(option)
                    }
                }
            }

            if headphones.callVoiceSetting != nil {
                SectionTitle("Voice Setting")
                    .padding(.top, 8)
                ForEach(CallVoiceSetting.allCases) { option in
                    SelectableRow(
                        systemImage: option.systemImage,
                        title: option.title,
                        isActive: headphones.callVoiceSetting == option
                    ) {
                        EmptyView()
                    } action: {
                        headphones.select(option)
                    }
                }
            }

            if let voiceAware = headphones.voiceAwareEnabled {
                SectionTitle("Voice Aware")
                    .padding(.top, 8)
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
                        isActive: voiceAware && headphones.voiceAwareLevel == option
                    ) {
                        EmptyView()
                    } action: {
                        headphones.select(option)
                    }
                }
            }
        }
    }
}
