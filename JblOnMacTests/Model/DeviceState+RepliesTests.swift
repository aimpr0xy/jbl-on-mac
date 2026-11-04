@testable import JblOnMac
import Testing

struct DeviceStateRepliesTests {
    /// Applies each reply in order and returns whether `DeviceState` handled it.
    private func apply(_ replies: [JBLReply], to state: inout DeviceState) -> [Bool] {
        replies.map { state.apply($0) }
    }

    @Test func storesAudioSettings() {
        var state = DeviceState()
        let handled = apply([
            .listeningMode(.ambientAware), .noiseCancelingLevel(3), .ambientAwareLevel(5), .balance(-4)
        ], to: &state)
        #expect(handled == [true, true, true, true])
        #expect(state.mode == .ambientAware)
        #expect(state.noiseCancelingLevel == 3)
        #expect(state.ambientAwareLevel == 5)
        #expect(state.balance == -4)
    }

    @Test func storesControlSettings() {
        var state = DeviceState()
        let handled = apply([
            .volumeLimiter(true), .soundLevelOptimizer(false), .voiceAware(enabled: true, level: .high)
        ], to: &state)
        #expect(handled == [true, true, true])
        #expect(state.volumeLimiterEnabled == true)
        #expect(state.soundLevelOptimizerEnabled == false)
        #expect(state.voiceAwareEnabled == true)
        #expect(state.voiceAwareLevel == .high)
    }

    @Test func gestureControlsAreStoredPerSide() {
        var state = DeviceState()
        let handled = apply([.gestureControl(.left, .volume)], to: &state)
        #expect(handled == [true])
        #expect(state.gestureControl(for: .left) == .volume)
        #expect(state.gestureControl(for: .right) == nil)

        _ = apply([.gestureControl(.right, nil)], to: &state)
        #expect(state.gestureControl(for: .left) == .volume)
        #expect(state.gestureControl(for: .right) == nil)
    }

    @Test func batteryPartsGoToTheirOwnFields() {
        var state = DeviceState()
        let handled = apply([
            .battery(.left, percent: 80), .battery(.right, percent: 70), .battery(.chargingCase, percent: 60)
        ], to: &state)
        #expect(handled == [true, true, true])
        #expect(state.leftBattery == 80)
        #expect(state.rightBattery == 70)
        #expect(state.caseBattery == 60)
    }

    @Test func leavesRepliesThatNeedMoreThanAStoredValueToTheController() {
        var state = DeviceState()
        let handled = apply([
            .acknowledged(group: 0x41, status: 0), .downloadStarted(length: 1, chunks: 1),
            .downloadFinished, .firmware("3.7.0"), .caseFirmware("1.0.0")
        ], to: &state)
        #expect(handled == [false, false, false, false, false])
        #expect(state.info.firmware == nil)
    }
}
