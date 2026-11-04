import SwiftUI

/// Call features screen, reached from the Calls row. Each row only shows once the
/// headphones report its state; the multi-option ones open their own screen.
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

            soundLevelOptimizerRow
            soundSettingRow
            voiceSettingRow
            voiceAwareRow
        }
    }

    @ViewBuilder
    private var soundLevelOptimizerRow: some View {
        if let optimizer = headphones.state.soundLevelOptimizerEnabled {
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
    }

    @ViewBuilder
    private var soundSettingRow: some View {
        if let sound = headphones.state.callSoundSetting {
            SelectableRow(
                systemImage: "waveform",
                title: "Sound Setting",
                subtitle: String(localized: sound.title),
                isActive: true
            ) {
                DisclosureChevron()
            } action: {
                screen = .callSound
            }
        }
    }

    @ViewBuilder
    private var voiceSettingRow: some View {
        if let voice = headphones.state.callVoiceSetting {
            SelectableRow(
                systemImage: "mic",
                title: "Voice Setting",
                subtitle: String(localized: voice.title),
                isActive: true
            ) {
                DisclosureChevron()
            } action: {
                screen = .callVoice
            }
        }
    }

    @ViewBuilder
    private var voiceAwareRow: some View {
        if let voiceAware = headphones.state.voiceAwareEnabled {
            SelectableRow(
                systemImage: "person.wave.2",
                title: "Voice Aware",
                subtitle: voiceAwareDescription(enabled: voiceAware),
                isActive: voiceAware
            ) {
                DisclosureChevron()
            } action: {
                screen = .voiceAware
            }
        }
    }

    /// "Off", or the selected level's name.
    private func voiceAwareDescription(enabled: Bool) -> String? {
        guard enabled else { return String(localized: "Off") }
        return headphones.state.voiceAwareLevel.map { String(localized: $0.title) }
    }
}
