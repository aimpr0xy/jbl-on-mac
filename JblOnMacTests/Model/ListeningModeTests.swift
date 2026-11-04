import Foundation
@testable import JblOnMac
import Testing

struct ListeningModeTests {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    @Test(arguments: [
        (ListeningMode.off, "Off", "slash.circle"),
        (.noiseCanceling, "Noise Canceling", "waveform.slash"),
        (.ambientAware, "Ambient Aware", "ear"),
        (.talkThru, "Talk Thru", "person.wave.2")
    ])
    func listening(_ mode: ListeningMode, _ title: String, _ image: String) {
        #expect(mode.id == mode.rawValue)
        #expect(mode.rawValue == title)
        #expect(ListeningMode(rawValue: title) == mode)
        #expect(text(mode.title) == title)
        #expect(mode.systemImage == image)
    }

    @Test func flaggedModesExcludeOffAndKeepFlagOrder() {
        #expect(ListeningMode.flagged == [.noiseCanceling, .ambientAware, .talkThru])
        #expect(ListeningMode.allCases.count == 4)
        #expect(ListeningMode(rawValue: "nope") == nil)
    }
}
