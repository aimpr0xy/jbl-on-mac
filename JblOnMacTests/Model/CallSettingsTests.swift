import Foundation
@testable import JblOnMac
import Testing

struct CallSettingsTests {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    @Test(arguments: [
        (CallSoundSetting.natural, UInt8(0), "Natural", "waveform"),
        (.increasedTreble, 1, "Increased Treble", "hifispeaker"),
        (.increasedBass, 2, "Increased Bass", "hifispeaker.fill")
    ])
    func callSound(_ mode: CallSoundSetting, _ raw: UInt8, _ title: String, _ image: String) {
        #expect(mode.rawValue == raw)
        #expect(mode.id == raw)
        #expect(CallSoundSetting(rawValue: raw) == mode)
        #expect(text(mode.title) == title)
        #expect(mode.systemImage == image)
    }

    @Test(arguments: [
        (CallVoiceSetting.natural, UInt8(0), "Natural", "mic"),
        (.powerful, 1, "Powerful", "mic.fill"),
        (.bright, 2, "Bright", "sparkles")
    ])
    func callVoice(_ mode: CallVoiceSetting, _ raw: UInt8, _ title: String, _ image: String) {
        #expect(mode.rawValue == raw)
        #expect(mode.id == raw)
        #expect(CallVoiceSetting(rawValue: raw) == mode)
        #expect(text(mode.title) == title)
        #expect(mode.systemImage == image)
    }

    @Test(arguments: [
        (VoiceAwareLevel.low, UInt8(1), "Low", "speaker.wave.1"),
        (.mid, 2, "Mid", "speaker.wave.2"),
        (.high, 3, "High", "speaker.wave.3")
    ])
    func voiceAware(_ level: VoiceAwareLevel, _ raw: UInt8, _ title: String, _ image: String) {
        #expect(level.rawValue == raw)
        #expect(level.id == raw)
        #expect(VoiceAwareLevel(rawValue: raw) == level)
        #expect(text(level.title) == title)
        #expect(level.systemImage == image)
    }

    @Test func callSettingCasesAreExhaustiveAndUnknownRawValuesFail() {
        #expect(CallSoundSetting.allCases.count == 3)
        #expect(CallVoiceSetting.allCases.count == 3)
        #expect(VoiceAwareLevel.allCases.map(\.rawValue) == [1, 2, 3])
        #expect(CallSoundSetting(rawValue: 3) == nil)
        #expect(CallVoiceSetting(rawValue: 3) == nil)
        #expect(VoiceAwareLevel(rawValue: 0) == nil)
    }
}
