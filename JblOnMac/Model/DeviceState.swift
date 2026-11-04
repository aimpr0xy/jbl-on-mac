/// Everything the headphones have reported (or that was set optimistically) for the selected
/// device. Every value is nil until known. Replacing it with `DeviceState()` resets all of it,
/// so a new field can't be forgotten when switching devices.
struct DeviceState {
    /// Model, firmware and other details from the Device Information service.
    var info = DeviceInfo()
    var mode: ListeningMode?
    var spatialMode: SpatialAudioMode?
    var smartMode: SmartAudioMode?
    /// Left / right sound balance (-16 left ... 16 right).
    var balance: Int?
    var volumeLimiterEnabled: Bool?
    var equalizer: EqualizerPreset?
    var soundLevelOptimizerEnabled: Bool?
    var callSoundSetting: CallSoundSetting?
    var callVoiceSetting: CallVoiceSetting?
    var voiceAwareEnabled: Bool?
    var voiceAwareLevel: VoiceAwareLevel?
    /// Noise canceling and ambient aware strength (1...7).
    var noiseCancelingLevel: Int?
    var ambientAwareLevel: Int?
    /// What the touch controls of each earbud do.
    var leftGestureControl: GestureControl?
    var rightGestureControl: GestureControl?
    var leftBattery: Int?
    var rightBattery: Int?
    var caseBattery: Int?

    func gestureControl(for side: EarbudSide) -> GestureControl? {
        side == .left ? leftGestureControl : rightGestureControl
    }

    /// The strength of a mode (1...7), or nil if it has none or it isn't known yet.
    func level(for mode: ListeningMode) -> Int? {
        switch mode {
        case .noiseCanceling: noiseCancelingLevel
        case .ambientAware: ambientAwareLevel
        case .off, .talkThru: nil
        }
    }
}
