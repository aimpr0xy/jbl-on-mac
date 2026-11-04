import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

struct EqualizerPresetTests {
    @Test(arguments: EqualizerPreset.allCases)
    func presetShape(_ preset: EqualizerPreset) {
        #expect(preset.gains.count == EqualizerPreset.frequencies.count)
        #expect(preset.tune230NCGains.count == 10)
        #expect(preset.id == preset.rawValue)
        #expect(EqualizerPreset(rawValue: preset.rawValue) == preset)
    }

    private struct PresetLook {
        let preset: EqualizerPreset
        let title: String
        let image: String
    }

    @Test func presetTitlesAndImages() {
        let expected = [
            PresetLook(preset: .off, title: "Off", image: "slash.circle"),
            PresetLook(preset: .studio, title: "Studio", image: "slider.horizontal.3"),
            PresetLook(preset: .bass, title: "Bass", image: "speaker.wave.2"),
            PresetLook(preset: .club, title: "Club", image: "sparkles"),
            PresetLook(preset: .extremeBass, title: "Extreme Bass", image: "waveform.path"),
            PresetLook(preset: .vocal, title: "Vocal", image: "mic"),
            PresetLook(preset: .jazz, title: "Jazz", image: "music.quarternote.3")
        ]
        for look in expected {
            #expect(String(localized: look.preset.title) == look.title)
            #expect(look.preset.systemImage == look.image)
        }
    }

    @Test func presetRawValuesAndFrequencies() {
        #expect(EqualizerPreset.allCases.map(\.rawValue) == [0, 7, 3, 1, 9, 2, 6])
        #expect(EqualizerPreset.frequencies.first == 32)
        #expect(EqualizerPreset.frequencies.last == 16000)
    }

    @Test func tuneBeam2Curves() {
        #expect(EqualizerPreset.off.gains == [Float](repeating: 0, count: 10))
        #expect(EqualizerPreset.studio.gains == [-2, -1, -1, -0.5, 0, 0, 0, 0, 0, 0])
        #expect(EqualizerPreset.bass.gains == [4, 4, 3, 2.5, 0.5, 0, 0, 0, 0, 0])
        #expect(EqualizerPreset.club.gains == [4, 3, 1, 2.5, -1.5, -1.5, 0, 1, 3, 4])
        #expect(EqualizerPreset.extremeBass.gains == [4, 4.5, 4.5, 3.5, -1, 0, 0, 2, 2, 0])
        #expect(EqualizerPreset.vocal.gains == [-1.5, -3, -3, 1, 3.5, 3.5, 3, 1.5, 0, -1.5])
        #expect(EqualizerPreset.jazz.gains == [2, 1.5, 1, 0, 0, 0, 0, 1, 1, 2])
    }

    @Test func tuneBeam2Headroom() {
        #expect(EqualizerPreset.off.headroom == 0)
        #expect(EqualizerPreset.studio.headroom == 0)
        #expect(EqualizerPreset.bass.headroom.bitPattern == 0x40EC_EDE7)
        #expect(EqualizerPreset.jazz.headroom.bitPattern == 0x4065_B853)
        #expect(EqualizerPreset.club.headroom.bitPattern == 0x40C4_4ADB)
        #expect(EqualizerPreset.vocal.headroom.bitPattern == 0x40D3_2A08)
        #expect(EqualizerPreset.extremeBass.headroom.bitPattern == 0x4107_58D1)
    }

    @Test func tune230NCCurves() {
        #expect(EqualizerPreset.off.tune230NCGains == [Float](repeating: 0, count: 10))
        #expect(EqualizerPreset.studio.tune230NCGains == [0, -2, -2, 0, 0, 0, 0, 0, 0, 0])
        #expect(EqualizerPreset.bass.tune230NCGains == [6, 3, 3, 2.5, 0.5, 0, 0, 0, 0, 0])
        #expect(EqualizerPreset.club.tune230NCGains == [4, 2, 1, 2.5, -1.5, -1.5, 0, 1, 2, 4])
        #expect(EqualizerPreset.vocal.tune230NCGains == EqualizerPreset.vocal.gains)
        #expect(EqualizerPreset.jazz.tune230NCGains == [1, 0, 1, 0, 0, 0, -2, 2, 0, 3])
        #expect(EqualizerPreset.extremeBass.tune230NCGains == EqualizerPreset.extremeBass.gains)
    }

    @Test func tune230NCHeadroom() {
        for preset in [EqualizerPreset.off, .studio, .vocal, .jazz] {
            #expect(preset.tune230NCHeadroom == 0)
        }
        #expect(EqualizerPreset.bass.tune230NCHeadroom.bitPattern == 0x414F_48E1)
        #expect(EqualizerPreset.club.tune230NCHeadroom.bitPattern == 0x412C_0DC8)
        #expect(EqualizerPreset.extremeBass.tune230NCHeadroom == EqualizerPreset.extremeBass.headroom)
    }
}
