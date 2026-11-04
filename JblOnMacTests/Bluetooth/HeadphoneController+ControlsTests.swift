import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

extension ControllerSuite {
    @MainActor
    struct ControlsTests {
        /// There is no peripheral in tests, so every command has to be ignored and leave the
        /// optimistic state alone; a UI toggle must not flip when nothing could be sent.
        @Test func commandsAreIgnoredWhileThereIsNoLink() {
            ControllerFixture.withController { controller in
                controller.select(ListeningMode.noiseCanceling)
                controller.setLevel(5, for: .noiseCanceling)
                controller.select(SpatialAudioMode.off)
                controller.select(SmartAudioMode.off)
                controller.setBalance(4)
                controller.select(EqualizerPreset.club)
                controller.select(GestureControl.volume, for: .left)
                controller.setVolumeLimiter(true)
                controller.setSoundLevelOptimizer(true)
                controller.select(CallSoundSetting.allCases[0])
                controller.select(CallVoiceSetting.allCases[0])
                controller.setVoiceAware(enabled: true)
                controller.select(VoiceAwareLevel.high)

                let state = controller.state
                #expect(state.mode == nil)
                #expect(state.noiseCancelingLevel == nil)
                #expect(state.spatialMode == nil)
                #expect(state.smartMode == nil)
                #expect(state.balance == nil)
                #expect(state.equalizer == nil)
                #expect(state.leftGestureControl == nil)
                #expect(state.volumeLimiterEnabled == nil)
                #expect(state.soundLevelOptimizerEnabled == nil)
                #expect(state.callSoundSetting == nil)
                #expect(state.callVoiceSetting == nil)
                #expect(state.voiceAwareEnabled == nil)
                #expect(state.voiceAwareLevel == nil)
                #expect(controller.pipeline == CommandPipeline())
            }
        }
    }
}
