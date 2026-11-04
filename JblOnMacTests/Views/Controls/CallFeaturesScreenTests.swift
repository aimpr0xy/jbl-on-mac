@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct CallFeaturesScreenTests {
    private func controller(_ configure: (inout DeviceState) -> Void = { _ in }) -> HeadphoneController {
        let controller = HeadphoneController()
        controller.selectedDevice = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA:BB", isConnected: true)
        controller.status = .connected
        controller.state = DeviceState()
        configure(&controller.state)
        return controller
    }

    private func calls(_ configure: (inout DeviceState) -> Void = { _ in }) -> CGFloat {
        let view = CallFeaturesScreen(headphones: controller(configure), screen: Box(Screen.calls).binding)
        return ViewHost.size(of: view).height
    }

    @Test func callFeaturesShowsOnlyReportedRows() {
        let none = calls()
        #expect(none > 0)
        let optimizer = calls { $0.soundLevelOptimizerEnabled = true }
        #expect(optimizer > none)
        #expect(calls { $0.soundLevelOptimizerEnabled = false } == optimizer)
        #expect(calls { $0.callSoundSetting = .increasedBass } > none)
        #expect(calls { $0.callVoiceSetting = .powerful } > none)
        #expect(calls { $0.voiceAwareEnabled = false } > none)
        let all = calls {
            $0.soundLevelOptimizerEnabled = false
            $0.callSoundSetting = .natural
            $0.callVoiceSetting = .natural
            $0.voiceAwareEnabled = true
            $0.voiceAwareLevel = .mid
        }
        #expect(all > optimizer)
    }

    @Test func voiceAwareRowShowsALevelSubtitleOnlyWhenEnabledAndKnown() {
        let off = calls { $0.voiceAwareEnabled = false }
        let onWithoutLevel = calls { $0.voiceAwareEnabled = true }
        let onWithLevel = calls {
            $0.voiceAwareEnabled = true
            $0.voiceAwareLevel = .high
        }
        // Off is spelled out, an enabled feature with no known level has no subtitle.
        #expect(off > onWithoutLevel)
        #expect(onWithLevel == off)
        // The level is ignored while the feature is off.
        #expect(calls {
            $0.voiceAwareEnabled = false
            $0.voiceAwareLevel = .low
        } == off)
    }
}
