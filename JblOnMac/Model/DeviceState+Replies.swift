extension DeviceState {
    /// Stores the value a reply carries. Returns false for replies that need more than a stored
    /// value (acknowledgements, firmware and equalizer downloads), which the controller handles.
    mutating func apply(_ reply: JBLReply) -> Bool {
        applyAudio(reply) || applyControls(reply) || applyBattery(reply)
    }

    private mutating func applyAudio(_ reply: JBLReply) -> Bool {
        switch reply {
        case let .listeningMode(mode): self.mode = mode
        case let .noiseCancelingLevel(level): noiseCancelingLevel = level
        case let .ambientAwareLevel(level): ambientAwareLevel = level
        case let .spatialAudio(mode): spatialMode = mode
        case let .smartAudio(mode): smartMode = mode
        case let .balance(value): balance = value
        case let .equalizer(preset): equalizer = preset
        default: return false
        }
        return true
    }

    private mutating func applyControls(_ reply: JBLReply) -> Bool {
        switch reply {
        case let .volumeLimiter(enabled): volumeLimiterEnabled = enabled
        case let .soundLevelOptimizer(enabled): soundLevelOptimizerEnabled = enabled
        case let .callSound(setting): callSoundSetting = setting
        case let .callVoice(setting): callVoiceSetting = setting
        case let .gestureControl(side, control): setGestureControl(control, for: side)
        case let .voiceAware(enabled, level):
            voiceAwareEnabled = enabled
            voiceAwareLevel = level
        default: return false
        }
        return true
    }

    private mutating func applyBattery(_ reply: JBLReply) -> Bool {
        guard case let .battery(part, percent) = reply else { return false }
        switch part {
        case .left: leftBattery = percent
        case .right: rightBattery = percent
        case .chargingCase: caseBattery = percent
        }
        return true
    }

    private mutating func setGestureControl(_ control: GestureControl?, for side: EarbudSide) {
        switch side {
        case .left: leftGestureControl = control
        case .right: rightGestureControl = control
        }
    }
}
