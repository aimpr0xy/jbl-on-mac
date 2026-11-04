@testable import JblOnMac
import SwiftUI
import Testing

@MainActor
struct CallSettingScreensTests {
    private func controller(_ configure: (inout DeviceState) -> Void = { _ in }) -> HeadphoneController {
        let controller = HeadphoneController()
        controller.selectedDevice = JBLDevice(name: "JBL Tune 230NC TWS", address: "AA:BB", isConnected: true)
        controller.status = .connected
        controller.state = DeviceState()
        configure(&controller.state)
        return controller
    }

    private func sound(_ configure: (inout DeviceState) -> Void = { _ in }) -> CGSize {
        ViewHost.size(of: CallSoundScreen(headphones: controller(configure), screen: Box(Screen.callSound).binding))
    }

    private func voice(_ configure: (inout DeviceState) -> Void = { _ in }) -> CGSize {
        ViewHost.size(of: CallVoiceScreen(headphones: controller(configure), screen: Box(Screen.callVoice).binding))
    }

    private func aware(_ configure: (inout DeviceState) -> Void = { _ in }) -> CGSize {
        ViewHost.size(of: VoiceAwareScreen(headphones: controller(configure), screen: Box(Screen.voiceAware).binding))
    }

    @Test func soundAndVoiceScreensListEveryOption() {
        let soundBase = sound()
        let voiceBase = voice()
        #expect(soundBase.height > 0)
        #expect(soundBase.height == voiceBase.height)
        for option in CallSoundSetting.allCases {
            #expect(sound { $0.callSoundSetting = option }.height == soundBase.height)
        }
        for option in CallVoiceSetting.allCases {
            #expect(voice { $0.callVoiceSetting = option }.height == voiceBase.height)
        }
    }

    @Test func voiceAwareScreenHasAnExtraOffRow() {
        #expect(aware().height > sound().height)
    }

    @Test func voiceAwareScreenRendersEveryState() {
        let base = aware()
        #expect(aware { $0.voiceAwareEnabled = false } == base)
        #expect(aware { $0.voiceAwareEnabled = true } == base)
        for level in VoiceAwareLevel.allCases {
            #expect(aware {
                $0.voiceAwareEnabled = true
                $0.voiceAwareLevel = level
            } == base)
        }
    }
}
