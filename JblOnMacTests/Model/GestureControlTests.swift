import Foundation
@testable import JblOnMac
import Testing

struct GestureControlTests {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    @Test func earbudSides() {
        #expect(EarbudSide.left.opposite == .right)
        #expect(EarbudSide.right.opposite == .left)
        #expect(EarbudSide.left.id == .left)
        #expect(EarbudSide.left.slots == [0x06, 0x07, 0x08, 0x0C])
        #expect(EarbudSide.right.slots == [0x09, 0x0A, 0x0B, 0x0E])
        #expect(text(EarbudSide.left.touchControlsTitle) == "Left Touch Controls")
        #expect(text(EarbudSide.right.touchControlsTitle) == "Right Touch Controls")
    }

    struct GestureExpectation {
        let control: GestureControl
        let title: String
        let image: String
        let leftActions: String
        let rightActions: String
    }

    @Test(arguments: [
        GestureExpectation(control: .none, title: "None", image: "slash.circle",
                           leftActions: "00 00 00 00", rightActions: "00 00 00 00"),
        GestureExpectation(control: .ambientSound, title: "Ambient Sound Control", image: "ear.and.waveform",
                           leftActions: "09 04 00 A1", rightActions: "0B 04 00 A1"),
        GestureExpectation(control: .volume, title: "Volume Control", image: "speaker.wave.2",
                           leftActions: "08 05 06 A1", rightActions: "08 05 06 A1"),
        GestureExpectation(control: .playback, title: "Playback Control", image: "playpause",
                           leftActions: "01 02 00 A1", rightActions: "01 02 00 A1")
    ])
    func gesture(_ expected: GestureExpectation) {
        let control = expected.control
        #expect(control.id == control)
        #expect(text(control.title) == expected.title)
        #expect(control.systemImage == expected.image)
        #expect(control.actions(for: .left) == bytes(expected.leftActions))
        #expect(control.actions(for: .right) == bytes(expected.rightActions))
        #expect(GestureControl(actions: bytes(expected.leftActions), side: .left) == control)
        #expect(GestureControl(actions: bytes(expected.rightActions), side: .right) == control)
    }

    @Test func rightSideAcceptsLeftActionsButNotViceVersa() {
        #expect(GestureControl(actions: bytes("09 04 00 A1"), side: .right) == .ambientSound)
        #expect(GestureControl(actions: bytes("0B 04 00 A1"), side: .left) == nil)
    }

    @Test func unknownActionsAreNil() {
        #expect(GestureControl(actions: [], side: .left) == nil)
        #expect(GestureControl(actions: bytes("01 02 03 04"), side: .right) == nil)
    }

    @Test func noneIsListedFirst() {
        #expect(GestureControl.allCases.first == GestureControl.none)
    }
}
