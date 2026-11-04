import Foundation
@testable import JblOnMac
import Testing

struct SmartAudioModeTests {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    @Test(arguments: [
        (SmartAudioMode.off, "Off", "slash.circle", "C5 00 2E 00 18 01 FF FF"),
        (.audio, "Audio Mode", "music.note", "00 01 2E 00 18 01 FF FF"),
        (.video, "Video Mode", "play.rectangle", "C5 00 2E 00 78 00 FF FF")
    ])
    func smartAudio(_ mode: SmartAudioMode, _ title: String, _ image: String, _ hex: String) {
        #expect(mode.payload == bytes(hex))
        #expect(SmartAudioMode(payload: bytes(hex)) == mode)
        #expect(mode.id == mode)
        #expect(text(mode.title) == title)
        #expect(mode.systemImage == image)
    }

    @Test func smartAudioRejectsUnknownPayloads() {
        #expect(SmartAudioMode(payload: []) == nil)
        #expect(SmartAudioMode(payload: bytes("C5 00 2E 00 18 01 FF")) == nil)
        #expect(SmartAudioMode(payload: bytes("00 00 00 00 00 00 00 00")) == nil)
        #expect(Set(SmartAudioMode.allCases.map(\.payload)).count == 3)
    }
}
