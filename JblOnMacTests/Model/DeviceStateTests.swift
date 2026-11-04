import CoreBluetooth
import Foundation
@testable import JblOnMac
import Testing

struct DeviceStateTests {
    @Test func gestureControlPerSide() {
        var state = DeviceState()
        #expect(state.gestureControl(for: .left) == nil)
        state.leftGestureControl = .volume
        state.rightGestureControl = .playback
        #expect(state.gestureControl(for: .left) == .volume)
        #expect(state.gestureControl(for: .right) == .playback)
    }

    @Test func levelPerMode() {
        var state = DeviceState()
        #expect(state.level(for: .noiseCanceling) == nil)
        state.noiseCancelingLevel = 3
        state.ambientAwareLevel = 5
        #expect(state.level(for: .noiseCanceling) == 3)
        #expect(state.level(for: .ambientAware) == 5)
        #expect(state.level(for: .off) == nil)
        #expect(state.level(for: .talkThru) == nil)
    }
}
