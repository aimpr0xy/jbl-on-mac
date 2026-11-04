import Foundation
@testable import JblOnMac
import Testing

struct SpatialAudioModeTests {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    @Test(arguments: [
        (SpatialAudioMode.off, UInt8(1), "Off", "slash.circle"),
        (.fixed, 2, "Fixed", "person.spatialaudio.stereo.fill"),
        (.headTracking, 3, "Head Tracking", "person.spatialaudio.3d.fill")
    ])
    func spatial(_ mode: SpatialAudioMode, _ raw: UInt8, _ title: String, _ image: String) {
        #expect(mode.rawValue == raw)
        #expect(mode.id == raw)
        #expect(SpatialAudioMode(rawValue: raw) == mode)
        #expect(text(mode.title) == title)
        #expect(mode.systemImage == image)
    }

    @Test func spatialRejectsUnknownBytes() {
        #expect(SpatialAudioMode(rawValue: 0) == nil)
        #expect(SpatialAudioMode(rawValue: 4) == nil)
        #expect(SpatialAudioMode.allCases.count == 3)
    }
}
